#!/bin/bash

curl --header "Content-Type: application/json" --data "{\"username\":\"madsdk\",\"password\":\"secret\"}" http://localhost:8001/authenticate -c cookies.txt
