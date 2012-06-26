dbox = require 'dbox'
express = require 'express'
fs = require 'fs'
userdb = require './userdb'
dropbox = require './dropbox'
shareserver = require('share').server
shareclient = require('share').client
RedisStore = require('connect-redis')(express)
connect = require 'connect'

# "Defines"
PORT = 8001
PERSISTINTERVAL = 60000

# Global variables
exports = this
sessionStore = new RedisStore
userdb = new userdb.UserDB()

class HTTPSServer
    constructor: (key_file, cert_file) ->
        @userdb = userdb
        options = {
            key : fs.readFileSync(key_file),
            cert : fs.readFileSync(cert_file)
        }
        @server = express.createServer(options)
        @server.use (req, res, next) ->
            res.header 'Access-Control-Allow-Origin', 'http://localhost:8000'
            res.header 'Access-Control-Allow-Credentials', 'true'
            res.header 'Access-Control-Allow-Headers', 'Content-Type'
            next()
        @server.use(express.cookieParser())
        @server.use(express.session({ store: sessionStore, secret: "monster truck" }))

        # ShareJS initialization
        @shareBufferState = {} # This is used to show whether a buffer is dirty or not.
        setInterval(
            (() =>
                @persistDirtyShareBuffers()), PERSISTINTERVAL)

        options =
            db:
                type:'redis'
            auth: @sharejsAuth,
            browserChannel:
                cors:"*"
        shareserver.attach(@server, options)
        @server.model.on 'pre-create', (docName, callback) =>
            owner = docName.split('+')[0]
            pathTokens = docName.split('+')
            pathTokens.splice(0, 1)
            path = pathTokens.join('/')

            @accessFileStore 'read', owner, path, null, (fileData, error) =>
                if error
                    console.log 'Error reading preload data' + error #DEBUG
                    callback error, null
                else
                    console.log 'Read preload data.' #DEBUG
                    @shareBufferState[docName] = null
                    callback null, fileData.toString('utf8') #TODO - encoding may be wrong here!

        @server.model.on 'applyOp', (docName, opData, snapshot, oldSnapshot) =>
            console.log 'applyOp', docName #DEBUG
            @shareBufferState[docName] = snapshot

        # Add a custom body parser that also buffers the raw body of the request if needed.
        @server.use (req, res, next) ->
            data = ''
            req.setEncoding 'binary'
            req.on 'data', (chunk) ->
                data += chunk.toString('binary')
            req.on 'end', () ->
                # Check whether content is json - and parse it if it is.
                if req.headers['content-type']?
                    for content_type in req.headers['content-type'].split(";")
                        if content_type.replace(/^\ +/g, '') == 'application/json'
                            try
                                req.body = JSON.parse data
                            catch error
                                console.log 'Error parsing body as JSON.', error
                        else if content_type.replace(/^\ +/g, '') == 'application/octet-stream'
                            req.raw_body = data
                else
                    # Store the raw body.
                    req.raw_body = data

                next()

        @server.listen(PORT)

        # Test code.
        @server.use(express.static(__dirname + '/test/sharetest')) #DEBUG

        # Open a file (sharejs)
        @server.get '/open/:username/*', (req, res) =>
            # Create a sharejs path.
            sharejsBuffer = req.params.username + "+" + req.params[0].replace("/", "+")
            console.log "Redirecting to", "/channel/" + sharejsBuffer #DEBUG
            res.redirect('/channel/' + sharejsBuffer)

        # Read a file.
        @server.get '/store/:username/*', (req, res) =>
            console.log req.headers

            # Check credentials.
            @checkCredentials req, res, RIGHTS['read'], () =>
                # We have authenticated (otherwise this function would not be called...)
                # Access the store.
                @httpAccessFileStore 'read', req, res

        @server.put '/store/:username/*', (req, res) =>
            @checkCredentials req, res, RIGHTS['write'], () =>
                if not req.raw_body?
                    res.send 'Content is missing.', 403
                    return

                @httpAccessFileStore 'write-raw', req, res

        # Write, delete, make directory, grant access.
        @server.post '/store/:username/*', (req, res) =>
            # Check that the operation parameter is set.
            if not req.body.operation?
                res.send 'Operation parameter is missing.', 403
                return

            # WRITE
            if req.body.operation == 'write'
                @checkCredentials req, res, RIGHTS['write'], () =>
                    # Check that the content is there.
                    if not req.body.content?
                        res.send 'Content parameter is missing.', 403
                        return

                    # We have authenticated (otherwise this function would not be called...)
                    @httpAccessFileStore 'write', req, res

            # UNLINK
            else if req.body.operation == 'unlink'
                @checkCredentials req, res, RIGHTS['unlink'], () =>
                    # We have authenticated (otherwise this function would not be called...)
                    @httpAccessFileStore 'unlink', req, res

            # MKDIR
            else if req.body.operation == 'mkdir'
                @checkCredentials req, res, RIGHTS['write'], () =>
                    @httpAccessFileStore 'mkdir', req, res

            # GRANT
            else if req.body.operation == 'grant'
                # Check that all parameters are there.
                if (not req.body.recipient?) or (not req.body.type?) or (not req.body.rights?)
                    res.send 'One or more required parameters are missing.', 403
                    return

                # Expires is allowed to be null - but if it's there we need to use it of course
                expires = null
                if req.body.expires?
                    expires = req.body.expires

                @checkCredentials req, res, req.body.rights << 4, () =>
                    # We have authenticated (otherwise this function would not be called...)
                    @userdb.grantAccess req.session.user, req.body.recipient, req.params.username, req.params[0], req.body.type, req.body.rights, expires, (error) ->
                        if error
                            res.send error, 500 # DEBUG: consider how to report these errors
                        else
                            res.send "Successfully granted access."

        # Authenticate.
        @server.post '/authenticate', (req, res) =>
            # Check for parameters.
            if (not req.body?) or (not req.body.username?) or (not req.body.password?)
                res.send {'success': false, 'error': 'Username or password parameter is missing.'}, 403
                return

            @authenticate req.body.username, req.body.password, (error) =>
                if (not error)
                    console.log "Authenticated user", req.body.username
                    req.session.user = req.body.username
                    res.send({'success' : true, 'redirect' : '/store/' + req.body.username })
                else
                    console.log "Error authenticating", req.body.username, "Error:", error
                    res.send {'success' : false, 'error' : error}, 403

        # Create new user.
        @server.post '/createuser', (req, res) =>
            # Check for parameters.
            if (not req.body.username?) or (not req.body.password?)
                res.send 'Username or password parameter is missing.', 403
                return

            @createUser req.body.username, req.body.password, (error) =>
                if error
                    console.log 'Error creating user', req.body.username
                    res.send 'Error creating user.', 403
                else
                    res.send {'success' : true, 'redirect' : '/store/' + req.body.username }
                    console.log 'Created user', req.body.username

    persistDirtyShareBuffers: () ->
        console.log 'Looking for buffers to persist.' #DEBUG
        for key of @shareBufferState
            console.log key #DEBUG
            if @shareBufferState[key] != null
                # This document is dirty - write it to the underlying fs.
                console.log 'Persisting buffer', key #DEBUG
                tokens = key.split '+'
                username = tokens[0]
                path = tokens[1..].join '/'
                @accessFileStore 'write', username, path, @shareBufferState[key], (reply, error) =>
                    if error
                        console.log 'Error persisting buffer to fs: ' + key
                    else
                        @shareBufferState[key] = null

    sharejsAuth: (agent, action) ->
        console.log "ShareJS auth", action.type, action.docName #DEBUG

        # If this is a 'connect' operation we have no way of knowing which document is being requested yet.
        if action.type == 'connect'
            action.accept()
            return

        # Find out which user is associated with this connection.
        if not agent.headers.cookie?
            # User is not authenticated - we never allow anonymous access.
            console.log "No cookie!" #DEBUG
            action.reject()
            return

        cookies = connect.utils.parseCookie(agent.headers.cookie)
        sessionStore.get cookies['connect.sid'], (err, data) =>
            if err or not data.user?
                console.log 'Error looking up user session through shareJS.'
                if err
                    console.log err
                action.reject()
                return
            else
                # Check that the user has sufficient rights to perform the action.
                username = data.user
                wantRights = 0
                if action.type == 'read'
                    wantRights = RIGHTS['read']
                else if action.type == 'create' or action.type == 'update'
                    wantRights = RIGHTS['write']
                else if action.type == 'delete'
                    wantRights = RIGHTS['unlink']

                owner = action.docName.split('+')[0]
                pathTokens = action.docName.split('+')
                pathTokens.splice(0, 1)
                path = pathTokens.join('/')

                userdb.checkAccess username, owner, path, wantRights, (error) =>
                    if error
                        console.log error
                        action.reject()
                    else
                        console.log "you're golden!" #DEBUG
                        action.accept()



                    # Try to preload the data into the sharejs buffer.
#                    console.log "Trying to load data into", action.docName #DEBUG
#                    shareclient.open action.docName, 'text', 'http://localhost:8001/doc', (error, doc) =>
#                        console.log "hest!" #DEBUG
#                        if error
#                            console.log error
#                            action.reject()
#                        else
#                            console.log "foo" #DEBUG
#                            @accessFileStore 'read', username, path, null, (fileData, error2) ->
#                                if error2
#                                    console.log error2
#                                    action.reject()
#                                else
#                                    console.log "woooot" #DEBUG
#                                    doc.submitOp {i:fileData, p:0}
#                                    doc.close()
#
#                                    # Everything checked out - accept this connection.
#                                    console.log "User", username, "accessed document", path, "with rights", wantRights
#                                    action.accept()



    authenticate: (username, password, cb) ->
        @userdb.lookup username, (err, doc) ->
            if (err)
                cb err
            else if (password != doc['password'])
                cb 'Invalid password given.'
            else
                cb null

    createUser: (username, password, cb) ->
        # Check that the user does not already exist.
        @userdb.lookup username, (err, doc) =>
            if (err)
                # We assume that the error is because the user did not exist - otherwise we will just react on the next db error.
                @userdb.createUser username, password, (err) ->
                    if err
                        cb err
                    else
                        cb null
            else
                # The user must already exist.
                cb 'Unable to create user. Perhaps it already exists?'

    checkCredentials: (req, res, needed_rights, next) ->
        owner = req.params.username
        path = req.params[0]
        session = req.session

        # Is the user even authenticated?
        if not session.user?
            res.send("You are not authenticated. Please log in before accessing files through this service.", 401)
            return

        # Here the db is contacted to check whether the current user is allowed access to the file.
        @userdb.checkAccess session.user, owner, path, needed_rights, (error) ->
            if error
                res.send error, 401
            else
                # Pass control on to the next function.
                if next
                    next req, res

    httpAccessFileStore: (accessType, req, res) ->
        if accessType == 'write'
            data = req.body.content
        else if accessType == 'write-raw'
            data = req.raw_body
        else
            data = null
        @accessFileStore accessType, req.params.username, req.params[0], data, (doc, error) ->
            if error
                console.log error
                res.send error, 500
            else
                res.header('Content-Type', doc.type)
                res.send doc.data

    accessFileStore: (accessType, username, path, data, callback) ->
        # Connect to that user's dbox store.
        @userdb.lookup username, (err, doc) ->
            if (err)
                callback null, "Error accessing user entry for user " + username
                return

            if doc['dropbox']
                # Set up the DropBox store.
                uid = doc['dropbox']['uid']
                oauth_token = doc['dropbox']['oauth_token']
                oauth_token_secret = doc['dropbox']['oauth_token_secret']
                userDbox = new dropbox.DboxServer(uid, oauth_token, oauth_token_secret)

                # READ
                if accessType == 'read'
                    # Find out whether we are accessing a file or directory.
                    userDbox.getMetadata path, (error, metadata) ->
                        if error
                            callback null, error
                        else
                            if (metadata['is_dir'])
                                # Get directory listing
                                callback metadata['contents'], null
                            else
                                # Get file contents.
                                userDbox.readFile path, (error, reply) ->
                                    if error
                                        callback null, error
                                    else
                                        callback { type: metadata['mime_type'], data: reply }, null

                # WRITE
                else if accessType == 'write' or accessType == 'write-raw'
                    userDbox.writeFile path, data, (error, reply) ->
                        if error
                            callback null, error
                        else
                            callback reply, null

                # UNLINK (remove)
                else if accessType == 'unlink'
                    userDbox.removeFile path, (error, reply) ->
                        if error
                            callback null, error
                        else
                            callback reply, null

                # MKDIR
                else if accessType == 'mkdir'
                    userDbox.makeDirectory path, (error, reply) ->
                        if error
                            callback null, error
                        else
                            callback reply, null
            else
                callback null, "User has no active store"



https_server = new HTTPSServer('ssl/server.key', 'ssl/server.crt')

console.log "FluidWebFS service running at https://localhost:" + PORT

# DEBUG - test code below
