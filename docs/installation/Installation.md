# Installing a FluidWebFS server

This document describes the required installation procedure for installing a FluidWebFS server. As this _is_ a research prototype, it requires a bit of work to install one of these :-) 

## Installing Node.js

Node.js is installed by simply downloading the installer from http://nodejs.org. The version we have been using is 0.6.19.


## Installing coffee-script

After having installed Node.js the __npm__ command line tool is available. To install Coffee Script you simply execute the following command in a terminal prompt:
    
    npm install -g coffee-script

This will install Coffee Script globally on the system.

## Getting the FluidWebFS source

For now FluidWebFS's source resides in Mads's DAIMI homedir. In order to check it out perform the following command in a terminal:

    export DEVELDIR=/some/path/where/you/store/source/code
    mkdir -p $DEVELDIR
    cd $DEVELDIR
    git clone ssh://fh.cs.au.dk/users/madsk/git/FluidWebFS.git

I assume that __$DEVELDIR__ is a valid directory path. You can substitute it with whatever you like.

## Installing dependencies

FluidWebFS depends on a plethora of Node.js modules. This section tries to explain how you can obtain and install them.

### The easy part

Most Node.js dependencies are listed in package.json and can thus be installed using npm:
    
    cd FluidWebFS
    npm install

There are also two other system dependencies: CouchDB and Redis. These can be installed in various ways depending on your system. On my Mac with MacPorts I install them by issuing these commands:

    sudo port install redis
    sudo port install couchdb

### The hard part

#### Installing ShareJS

Some dependencies must be built from source. This goes e.g., for Share.js.

    cd $DEVELDIR/FluidWebFS/node_modules
    git clone https://github.com/hci-au-dk/ShareJS.git share
    cd share
    npm install redis
    sudo npm link
    cake build
    cake webclient

Now that we have built Share.js we need to modify its browserchannel dependency.

    cd $DEVELDIR/FluidWebFS/node_modules/share/node_modules
    rm -rf browserchannel
    git clone https://github.com/hci-au-dk/node-browserchannel.git browserchannel

The above should do the trick, but if it doesn't work you may have to apply some more patches (these should be included in what you just checked out, but the following patching process is kept here for reference if an error occurs).

    cd $DEVELDIR
    svn checkout http://closure-library.googlecode.com/svn/trunk/ closure-library
    curl -O http://closure-compiler.googlecode.com/files/compiler-20120430.zip
    unzip compiler-20120430.zip
    mv compiler.jar closure-library/
    cd closure-library
    patch -p0 < $DEVELDIR/FluidWebFS/docs/installation/enable-with-credentials.patch
    cd $DEVELDIR/FluidWebFS/node_modules/share/node_modules/browserchannel
    git apply $DEVELDIR/FluidWebFS/docs/installation/browserchannel-makefile.patch
    cake webclient
    make
