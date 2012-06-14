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

Some dependencies must be built from source. This goes e.g., for Share.js. In the following is shown how to fetch the most recent version of Share.js - in our tests the latest commit was:

    commit 745ee1f49e051ae2aa62c2f30ec8d8e05ecabb21
    Merge: 57aede0 3d92362
    Author: Joseph Gentle <josephg@gmail.com>
    Date:   Mon May 21 20:57:50 2012 -0700

To fetch and build Share.js do this:

    cd $DEVELDIR/FluidWebFS/node_modules
    git clone https://github.com/josephg/ShareJS.git share
    cd share
    npm install redis
    sudo npm link
    cake build
    cake webclient

Now that we have built Share.js we need to do two modifications: 1) we need to apply our own patch to the Share.js server, and 2) we must replace its browserchannel dependency.

    cd $DEVELDIR/FluidWebFS/node_modules/share
    git apply $DEVELDIR/FluidWebFS/docs/installation/pre-create-event.patch


    cd $DEVELDIR/FluidWebFS/node_modules/share/node_modules
    rm -rf browserchannel
    git clone https://github.com/josephg/node-browserchannel.git browserchannel
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

In our tests the last commit in the node-browserchannel Git repos was this:

    commit 7522e83ff0e140b823fe899a7a44641c0657f988
    Author: Joseph <josephg@gmail.com>
    Date:   Sat May 12 12:10:39 2012 +1000

The Closure Library was checked out at revision __1961__.
