cradle = require 'cradle'
process = require 'process'

RIGHTS = {
    'read' : 1,
    'write' : 2,
    'modify' : 4,
    'unlink' : 8,
    'grant read' : 16,
    'grant write' : 32,
    'grant modify' : 64,
    'grant unlink' : 128
}

mayRead = (rights) ->
    return rights & RIGHTS['read']

mayWrite = (rights) ->
    return rights & RIGHTS['write']

mayModify = (rights) ->
    return rights & RIGHTS['modify']

mayUnlink = (rights) ->
    return rights & RIGHTS['unlink']

mayGrantRead = (rights) ->
    return rights & RIGHTS['grant read']

mayGrantWrite = (rights) ->
    return rights & RIGHTS['grant write']

mayGrantModify = (rights) ->
    return rights & RIGHTS['grant modify']

mayGrantUnlink = (rights) ->
    return rights & RIGHTS['grant unlink']

hasRights = (want, have) ->
    mask = 1

    for x in [0,1,2,3,4,5,6,7]
        if want & mask
            if not (have & mask)
                return false
        mask = mask << 1

    return true

prefixMatch = (tokenPath, requestedPath, tokenType) ->
    # Remove any trailing /s
    tokenPath = tokenPath.replace(/\/$/, '')
    requestedPath = requestedPath.replace(/\/$/, '')

    # If the token is longer than the path we don't need to check at all.
    if tokenPath.length > requestedPath.length
        return false

    # Check char for char if the prefix matches.
    x = 0
    while x < tokenPath.length
        if tokenPath[x] != requestedPath[x]
            return false
        x += 1

    # The prefix matches so far. Now check to see if the extension is legal...
    if tokenType == 'file'
        # Files must match 100%
        if tokenPath.length != requestedPath.length
            return false
    else
        # type == 'dir'. We need a 100% match or a '/' as the next char.
        if tokenPath.length != requestedPath.length and requestedPath[x] != '/'
            return false

    return true

class UserDB
    constructor: () ->
        # Connect to the local couchdb.
        @db = new (cradle.Connection)('http://localhost', 5984, {'cache' : false, 'raw' : false}).database('userdb')

        # Check that the database exists - and if not create it.
        @db.exists (error, exists) =>
            if (error)
                console.log 'Error connecting to database:', error
                process.exit 1
            else if (not exists)
                @createDatabase()


    createDatabase: () ->
        console.log 'Creating database userdb.'
        @db.create (error) =>
            if (error)
                console.log 'Error creating database.', error
                process.exit 1
            @db.exists (error, exists) ->
                if (error)
                    console.log 'Error creating database.', error
                    process.exit 1
                else if (not exists)
                    console.log 'Error creating database.'
                    process.exit 1


    lookup: (username, cb) ->
        @db.get username, (error, doc) ->
            if (error)
                cb error, null
            else
                cb null, doc

    createUser: (username, password, cb) ->
        @db.save username, { 'password' : password }, (error, doc) ->
            if error
                cb error
            else
                cb null

    # Pre-requisite: This method must _only_ be called _after_ checking that the issuer has the appropriate rights.
    grantAccess: (issuer, recipient, owner, path, type, rights, expires, cb) ->
        # Create the token and update the rights dictionary of the recipient's user entry.
        token = { 'owner' : owner, 'issuer' : issuer, 'expires' : expires, 'path' : path, 'type' : type, 'rights' : rights }
        # First we update the recipient's user entry with the new token.
        @db.get recipient, (error, doc) =>
            if error
                cb error
                return

            # Make sure that the doc has a rights object
            if not doc.rights?
                doc.rights = {}

            # Make sure that the doc has a list for tokens with that owner
            if not doc.rights[owner]?
                doc.rights[owner] = []

            # Append the token.
            # TODO: maybe we should prune old tokens here?
            doc.rights[owner].push token

            @db.save recipient, doc, (error, res) =>
                if error
                    cb error
                    return

                # Then we update the token_holders list of the owner.
                @db.get owner, (error, doc) =>
                    if error
                        cb error
                        return

                    if not doc.token_holders?
                        doc.token_holders = []

                    hasTokenHolder = false
                    for x in doc.token_holders
                        if x == recipient
                            hasTokenHolder = true
                    if not hasTokenHolder
                        doc.token_holders.push recipient

                    # And save the object in the database
                    @db.save owner, doc, (error, res) ->
                        if error
                            cb error
                            return

                        cb null

    checkAccess: (user, owner, path, want_rights, cb) ->
        # Check whether the given user is allowed to access the given path.
        # If the user accessing the data is also the owner we don't need to check anything.
        if user == owner
            cb null
            return

        # Lookup the user's entry in the database to find his rights tokens.
        @db.get user, (error, doc) ->
            if error
                cb error # DEBUG: Consider how to report this error
                return

            if doc['rights'] and doc['rights'][owner]
                rightsTokens = doc['rights'][owner]
                for token in rightsTokens
                    # Check that the token has not expired.
                    if token['expires']
                        now = new Date()
                        tokenDate = new Date(token['expires'])
                        if tokenDate < now
                            cb "Token has expired. Access denied to " + path
                            return

                    # Check if the token is valid for this path.
                    if (token['type'] == 'file' and token['path'] == path) or (token['type'] == 'dir' and prefixMatch(token['path'], path, token['type']))
                        if hasRights want_rights, token['rights']
                            # The user is allowed to access this file.
                            cb null
                            return

            cb 'User ' + user + ' is not allowed to access ' + path

exports.UserDB = UserDB
global.RIGHTS = RIGHTS