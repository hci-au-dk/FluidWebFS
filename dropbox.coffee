dbox = require 'dbox'
fs = require 'fs'

class DboxServer
    constructor: (uid, oauth_token, oauth_token_secret) ->
        # Load the configuration.
        @config = JSON.parse(fs.readFileSync('config.json', 'utf8'))

        # Authenticate to DropBox
        @dbox_app = dbox.app { "app_key" : @config["appkey"], "app_secret" : @config["appsecret"] }
        @client = @dbox_app.createClient( { "oauth_token" : oauth_token, "oauth_token_secret" : oauth_token_secret, "uid" : uid } )

    accountInfo: (cb) ->
        @client.account (status, reply) ->
            if status != 200
                cb "Error getting account info.", null
            else
                cb null, reply

    readFile: (path, cb) ->
        @client.get path, (status, reply) ->
            if status != 200
                cb reply, null
            else
                cb null, reply

    writeFile: (path, content, cb) ->
        @client.put path, content, (status, reply) ->
            if status != 200
                cb reply, null
            else
                cb null, reply

    removeFile: (path, cb) ->
        @client.rm path, (status,reply) ->
            if status != 200
                cb reply, null
            else
                cb null, reply

    getMetadata: (path, cb) ->
        @client.metadata path, (status, reply) ->
            if status != 200
                cb reply, null
            else
                cb null, reply

    makeDirectory: (path, cb) ->
        @client.mkdir path, (status, reply) ->
            if status != 200
                cb reply, null
            else
                cb null, reply


exports.DboxServer = DboxServer