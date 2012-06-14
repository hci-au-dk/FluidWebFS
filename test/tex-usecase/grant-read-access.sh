#!/bin/bash

USERNAME=$1
PASSWORD=$2
RECIPIENT=$3
SHAREPATH=$4

if [ "$USERNAME" = "" ] || [ "$PASSWORD" = "" ] || [ "$RECIPIENT" = "" ] || [ "$SHAREPATH" = "" ]; then 
    echo "Usage: ./upload-paper-folder.sh username password recipient path"
    echo "Example: ./upload-paper-folder.sh madsdk secret hrtest mypaper"
    exit 1
fi

# Log in.
curl --header "Content-Type: application/json" --data "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" http://localhost:8001/authenticate -c cookies.txt
echo ""

# Create a token for the recipient.
curl --header "Content-Type: application/json" --data "{\"operation\":\"grant\",\"recipient\":\"$RECIPIENT\",\"type\":\"dir\",\"rights\":1,\"expires\":null}" http://localhost:8001/store/$USERNAME/$SHAREPATH -b cookies.txt
