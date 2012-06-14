dbox = require 'dbox'
fs = require 'fs'

# Load the configuration.
config = JSON.parse(fs.readFileSync('config.json', 'utf8'))

# Connect to DropBox and ask for a request token.
dbox_app = dbox.app({ "app_key" : config["appkey"], "app_secret" : config["appsecret"]})
dbox_app.request_token((status, request_token) -> 
  console.log "Connect to this URL in a browser: "
  console.log request_token
)
