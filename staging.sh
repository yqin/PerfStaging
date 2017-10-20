#!/bin/bash

# GLOBAL settings
AUTHOR="Yong Qin (yongq@mellanox.com)"
DEBUG=0
VERBOSE=0
VERSION="0.1"

# GLOBAL functions
function Error () {
    local EXIT="$1"
    local MSG="$2"
    echo "`date +"%b %d %H:%M:%S"` ERROR: "$MSG"" >&2
    exit $EXIT
}


function Warning () {
    local MSG="$1"
    echo "`date +"%b %d %H:%M:%S"` WARNING: "$MSG"" >&2
}


function Info () {
    local MSG="$1"
    if [[ $VERBOSE -eq 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` INFO: "$MSG"" >&2
    fi  
}


function Debug () {
    local MSG="$1"
    if [[ $DEBUG -eq 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` DEBUG: "$MSG"" >&2
    fi  
}


function Usage () {
    echo "Usage: $0 "
    echo "  -d  debug mode"
    echo "  -h  this help page"
    echo "  -v  verbose mode"
}


# Retrieve command line options
while getopts ":dhv" OPT; do
    case $OPT in
        d)
            DEBUG=1
            ;;
        h)
            Usage
            ;;
        v)
            VERBOSE=1
            ;;
        \?)
            Error 1 "Invalid option: -${OPTARG}!"
            ;;
        :)
            Error 1 "Option -${OPTARG} requires an argument!"
            ;;
    esac
done

