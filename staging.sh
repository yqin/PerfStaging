#!/bin/bash

# ERROR Codes
# 1 - command line option error
# 2 - environment module error
#

# GLOBAL settings
AUTHOR="Yong Qin (yongq@mellanox.com)"
VERSION="0.1"

APP=""
APP_VER=""
BENCHMARK=""
COMPILER="intel"
COMPILER_VER="2017.4.196"
DEBUG=1
ENV_VARS=""
INPUT=""
MODULES=""
MPI="hpcx"
MPI_VER="1.9"
MPI_OPTS=""
MPI_CMD="mpirun"
VERBOSE=1


# GLOBAL functions
# Print error message
function Error () {
    local EXIT="$1"
    local MSG="$2"
    echo "`date +"%b %d %H:%M:%S"` ERROR: "$MSG"" >&2
    exit $EXIT
}


# Print warning message
function Warning () {
    local MSG="$1"
    echo "`date +"%b %d %H:%M:%S"` WARNING: "$MSG"" >&2
}


# Print info message
function Info () {
    local MSG="$1"
    if [[ $VERBOSE -eq 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` INFO: "$MSG"" >&2
    fi  
}


# Print debug message
function Debug () {
    local MSG="$1"
    if [[ $DEBUG -eq 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` DEBUG: "$MSG"" >&2
    fi  
}


# Load modules and exit if fail
function LoadModule () {
    if [[ -z "$1" ]]; then
        Error 2 "No module provided."
    fi

    Debug "module load $1"
    module load "$1" 2>&1 | grep "ERROR" > /dev/null

    if [[ $? == 0 ]]; then
        Error 2 "Failed to load modules $1."
    fi
}


# Setup compiler
function SetCompiler () {
    if [[ "${COMPILER}" == "intel" ]]; then
        LoadModule "${COMPILER}/compiler/${COMPILER_VER}"
    elif [[ "${COMPILER}" == "gnu" ]]; then
        if [[ "${COMPILER_VER}" != `gcc -v 2>&1 | awk 'END{print $3}'` ]]; then
            LoadModule "${COMPILER}/${COMPILER_VER}"
        fi
    else
        Error 2 "Unknown compiler ${COMPILER}/${COMPILER_VER}."
    fi

    Info "Compiler ${COMPILER}/${COMPILER_VER} loaded."
}


# Setup MPI
function SetMPI () {
    if [[ "${MPI}" == "hpcx" ]]; then
        if [[ "${COMPILER}" == "intel" ]]; then
            if [[ "${COMPILER_VER}" == "2017"* ]]; then
                LoadModule "${MPI}-${MPI_VER}/icc-2017"
            elif [[ "${COMPILER_VER}" == "2016"* ]]; then
                LoadModule "${MPI}-${MPI_VER}/icc-2016"
            else
                Error 2 "Unknown MPI ${MPI}-${MPI_VER}/icc-${COMPILER_VER}."
            fi
        elif [[ "${COMPILER}" == "gnu" ]]; then
            LoadModule "${MPI}-${MPI_VER}/gcc"
        else
            Error 2 "Unknown MPI ${MPI}-${MPI_VER}/${COMPILER}-${COMPILER_VER}."
        fi
    elif [[ "${MPI}" == "impi" ]]; then
        LoadModule "intel/${MPI}/${MPI_VER}"
    else
        Error 2 "Unknown MPI ${MPI}-${MPI_VER}."
    fi

    Info "MPI ${MPI}/${MPI_VER} loaded."
}


# Load extra modules
function SetModules () {
    if [[ -n "$MODULES" ]]; then
        LoadModule "$1"
    fi
}


# Setup extra environment variables
function SetEnvironment () {
    if [[ -n "$ENV_VARS" ]]; then
        export ${ENV_VARS}
    fi
}


function Usage () {
    echo "Usage: $0 TBD"
    echo "  -a,--app                Application"
    echo "     --app_ver            Application version"
    echo "  -b,--bench              Benchmark executable"
    echo "  -c,--compiler           Compiler"
    echo "     --compiler_ver       Compiler version"
    echo "  -d,--debug              Debug mode"
    echo "  -e,--env                Environment variables"
    echo "  -h,--help,--usage       This help page"
    echo "     --input              Input data for benchmark"
    echo "     --modules            Extra modules"
    echo "  -m,--mpi                MPI"
    echo "     --mpi_ver            MPI version"
    echo "     --mpi_opts           Extra MPI options"
    echo "  -v,--verbose            Verbose mode"
}


# Retrieve command line options
CMD_OPTS=`getopt \
    -o a:b:c:de:hm:v \
    -l app:,app_ver:,bench:,compiler:,compiler_ver:,debug,env:,help::,modules:,mpi:,mpi_ver:,mpi_opts:,usage,verbose \
    -n "$0" -- "$@"`

if [[ $? != 0 ]]; then
    Error 1 "Failed to parse command line options."
fi

eval set -- "$CMD_OPTS"

while true do OPT; do
    case "$1" in
        -a|--app)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    APP="$2"
                    Debug "APP=${APP}"
                    shift 2
                    ;;
            esac
            ;;
        --app_ver)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    APP_VER="$2"
                    Debug "APP_VER=${APP_VER}"
                    shift 2
                    ;;
            esac
            ;;
        -b|--bench)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    BENCHMARK="$2"
                    Debug "BENCHMARK=${BENCHMARK}"
                    shift 2
                    ;;
            esac
            ;;
        -c|--compiler)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    COMPILER="$2"
                    Debug "COMPILER=${COMPILER}"
                    shift 2
                    ;;
            esac
            ;;
        --compiler_ver)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    COMPILER_VER="$2"
                    Debug "COMPILER_VER=${COMPILER_VER}"
                    shift 2
                    ;;
            esac
            ;;
        -d|--debug)
            DEBUG=1
            shift
            ;;
        -e|--env)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    ENV_VARS="$2"
                    Debug "ENV_VARS=${ENV_VARS}"
                    shift 2
                    ;;
            esac
            ;;
        -h|--help|--usage)
            Usage
            shift
            ;;
        -i|--input)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    INPUT="$2"
                    Debug "INPUT=${INPUT}"
                    shift 2
                    ;;
            esac
            ;;
        --modules)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MODULES="$2"
                    Debug "MODULES=${MODULES}"
                    shift 2
                    ;;
            esac
            ;;
        -m|--mpi)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MPI="$2"
                    Debug "MPI=${MPI}"
                    shift 2
                    ;;
            esac
            ;;
        --mpi_ver)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MPI_VER="$2"
                    Debug "MPI_VER=${MPI_VER}"
                    shift 2
                    ;;
            esac
            ;;
        --mpi_opts)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MPI_OPTS="$2"
                    Debug "MPI_OPTS=${MPI_OPTS}"
                    shift 2
                    ;;
            esac
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            Error 1 "Internal error."
            ;;
    esac
done

# Setup environment
SetAPP
SetBenchmark
SetCompiler
SetMPI
SetModules
SetEnvironment
