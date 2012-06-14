#!/bin/bash

USERNAME=$1
PASSWORD=$2

if [ "$USERNAME" = "" ] || [ "$PASSWORD" = "" ]; then 
    echo "Usage: ./upload-paper-folder.sh username password"
    exit 1
fi

# Log in.
curl --header "Content-Type: application/json" --data "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" http://localhost:8001/authenticate -c cookies.txt
echo ""

# Create the folder.
curl --header "Content-Type: application/json" --data "{\"operation\":\"mkdir\"}" http://localhost:8001/store/$USERNAME/mypaper -b cookies.txt
echo ""

# Upload the files.
curl --upload-file mypaper/master.tex http://localhost:8001/store/$USERNAME/mypaper/master.tex -b cookies.txt
echo ""
curl --upload-file mypaper/abstract.tex http://localhost:8001/store/$USERNAME/mypaper/abstract.tex -b cookies.txt
echo ""
curl --upload-file mypaper/intro.tex http://localhost:8001/store/$USERNAME/mypaper/intro.tex -b cookies.txt
echo ""

