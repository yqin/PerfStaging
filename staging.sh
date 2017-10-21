#!/bin/bash

# ERROR Codes
# 1 - command line option error
# 2 - not an integer
EOPTARG=1
EINTEGER=2

# GLOBAL settings
AUTHOR="Yong Qin (yongq@mellanox.com)"
VERSION="0.1"

APP="OSU"
APP_VER="5.3.2"
BENCHMARK="osu_latency"
CLUSTER="DDDD"
COMPILERS=("intel")
COMPILER_VERS=("2017.4.196")
DEBUG=0
ENV_VARS=""
INPUT=""
JOB=""
MODE=""
MODULES=""
MPIS=("hpcx")
MPI_VERS=("1.9")
MPI_OPTS=("")
MPI_CMD="mpirun"
NODES=(1)
PPNS=(1)
THREADS=(1)
VERBOSE=0


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
    if [[ ${VERBOSE} == 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` INFO: "$MSG"" >&2
    fi  
}


# Print debug message
function Debug () {
    local MSG="$1"
    if [[ ${DEBUG} == 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` DEBUG: "$MSG"" >&2
    fi  
}


# Check if input value is a number or not
function IsNumber () {
    expr "$1" + 1 >/dev/null 2>&1
    return $?
}


# Load modules and exit if fail
function LoadModule () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    local MODULE=$1

    if [[ -n "${MODULE}" ]]; then
        cat >> "${JOB}" << EOF
module load ${MODULE}
EOF

        Info "Module ${MODULE} loaded."
    fi
}


# Sanity checking to make sure all required information is provided
function Sanitize () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    if [[ -z "${APP}" ]]; then
        Error ${EOPTARG} "Application not provided."
    fi

    if [[ -z "${APP_VER}" ]]; then
        Error ${EOPTARG} "Application version not provided."
    fi

    if [[ -z "${BENCHMARK}" ]]; then
        Error ${EOPTARG} "Benchmark not provided."
    fi

    if [[ -z "${CLUSTER}" ]]; then
        Error ${EOPTARG} "Cluster not provided."
    fi
}


# Setup compiler
function LoadCompiler () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    local COMPILER=$1
    local COMPILER_VER=$2

    if [[ "${COMPILER}" == "intel" ]]; then
        LoadModule "${COMPILER}/compiler/${COMPILER_VER}"
    elif [[ "${COMPILER}" == "gnu" ]]; then
        if [[ "${COMPILER_VER}" != `gcc -v 2>&1 | awk 'END{print $3}'` ]]; then
            LoadModule "${COMPILER}/${COMPILER_VER}"
        fi
    else
        Error ${EOPTARG} "Unknown compiler ${COMPILER}/${COMPILER_VER}."
    fi

    Info "Compiler ${COMPILER}/${COMPILER_VER} loaded."
}


# Setup MPI
function LoadMPI () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    local MPI=$1
    local MPI_VER=$2

    if [[ "${MPI}" == "hpcx" ]]; then
        if [[ "${COMPILER}" == "intel" ]]; then
            if [[ "${COMPILER_VER}" == "2017"* ]]; then
                LoadModule "${MPI}-${MPI_VER}/icc-2017"
            elif [[ "${COMPILER_VER}" == "2016"* ]]; then
                LoadModule "${MPI}-${MPI_VER}/icc-2016"
            else
                Error ${EOPTARG} "Unknown MPI ${MPI}-${MPI_VER}/icc-${COMPILER_VER}."
            fi
        elif [[ "${COMPILER}" == "gnu" ]]; then
            LoadModule "${MPI}-${MPI_VER}/gcc"
        else
            Error ${EOPTARG} "Unknown MPI ${MPI}-${MPI_VER}/${COMPILER}-${COMPILER_VER}."
        fi
    elif [[ "${MPI}" == "impi" ]]; then
        LoadModule "intel/${MPI}/${MPI_VER}"
    else
        Error ${EOPTARG} "Unknown MPI ${MPI}-${MPI_VER}."
    fi

    Info "MPI ${MPI}/${MPI_VER} loaded."
}


# Load extra modules
function LoadModules () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    if [[ -n "${MODULES}" ]]; then
        LoadModule "${MODULES}"
    fi

    #Debug "All loaded modules: `module -t list 2>&1 | awk 'NR>=2{print $1}'`"
}


# Setup extra environment variables
function LoadEnvironment () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    if [[ -n ${ENV_VARS} ]]; then
        cat >> "${JOB}" << EOF
export ${ENV_VARS}
EOF

        Info "Environment variables ${ENV_VARS} exported."
    fi

    #Debug "All environment variables: `env`"
}


# Build MPIRUN command line
function BuildMPI_CMD () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    echo
}


# Build job script
function BuildJob () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    local COMPILER=""
    local COMPILER_VER=""
    local MPI=""
    local MPI_VER=""
    local NODE=
    local PPN=
    local THREAD=

    # Permutate all combinations
    for COMPILER in ${COMPILERS[*]}; do

        for COMPILER_VER in ${COMPILER_VERS[*]}; do

            for MPI in ${MPIS[*]}; do

                for MPI_VER in ${MPI_VERS[*]}; do

                    for NODE in ${NODES[*]}; do

                        for PPN in ${PPNS[*]}; do

                            for THREAD in ${THREADS[*]}; do

                                # Define job script name
                                JOB="${APP}-${APP_VER}-${BENCHMARK}.${CLUSTER}.${COMPILER}-${COMPILER_VER}.${MPI}-${MPI_VER}.${MODE}.`printf \"%04d\" $((NODE * PPN * THREAD))`"

                                # Shell to be used
                                cat > "${JOB}" << EOF
#!${SHELL}
module purge
EOF

                                LoadCompiler "${COMPILER}" "${COMPILER_VER}"
                                LoadMPI "${MPI}" "${MPI_VER}"
                                LoadModules
                                LoadEnvironment
                                ShowJob

                            done # THREAD

                        done # PPN

                    done # NODE

                done # MPI_VER

            done # MPI

        done # COMPILER_VER

    done # COMPILER
}


# Show job script
function ShowJob () {
    Debug "Calling ${FUNCNAME[0]}($*)"

    local LINE

    while read LINE; do
        Debug "${LINE}"
    done < "${JOB}"
}


# Submit job script
function SubmitJob () {
    Debug "Calling ${FUNCNAME[0]}($*)"
}


function Usage () {
    echo "Usage: $0 TBD"
    echo "  -a,--app                Application"
    echo "     --app_ver            Application version"
    echo "  -b,--bench              Benchmark"
    echo "     --cluster            Cluster"
    echo "  -c,--compilers          Compilers"
    echo "     --compiler_vers      Compiler versions"
    echo "  -d,--debug              Debug mode"
    echo "  -e,--env                Environment variables"
    echo "  -h,--help,--usage       Help page (hcoll, mxm, ompi, sharp, ucx)"
    echo "  -i,--input              Input data for benchmark"
    echo "     --modules            Extra modules"
    echo "  -m,--mpis               MPI"
    echo "     --mpi_vers           MPI version"
    echo "     --mpi_opts           Extra MPI options"
    echo "  -n,--nodes              # of Nodes"
    echo "     --ppn                # of processes per node"
    echo "     --threads            # of threads per process"
    echo "  -v,--verbose            Verbose mode"
}


# Retrieve command line options
CMD_OPTS=`getopt \
    -o a:b:c:de:h::i:m:n:v \
    -l app:,app_ver:,bench:,cluster:,compilers:,compiler_vers:,debug,env:,help::,input:,modules:,mpis:,mpi_vers:,mpi_opts:,nodes:,ppn:,threads:,usage::,verbose \
    -n "$0" -- "$@"`

if [[ $? != 0 ]]; then
    Error ${EOPTARG} "Failed to parse command line options."
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
        --cluster)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    CLUSTER="$2"
                    Debug "CLUSTER=${CLUSTER}"
                    shift 2
                    ;;
            esac
            ;;
        -c|--compilers)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    COMPILER=(${2//,/ })
                    Debug "COMPILERS=(${COMPILERS[*]})"
                    shift 2
                    ;;
            esac
            ;;
        --compiler_vers)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    COMPILER_VER=(${2//,/ })
                    Debug "COMPILER_VERS=(${COMPILER_VERS[*]})"
                    shift 2
                    ;;
            esac
            ;;
        -d|--debug)
            DEBUG=1
            VERBOSE=1
            shift
            ;;
        -e|--env)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    ENV_VARS=${2//,/ }
                    Debug "ENV_VARS=${ENV_VARS}"
                    shift 2
                    ;;
            esac
            ;;
        -h|--help|--usage)
            case "$2" in
                "")
                    Usage
                    shift 2
                    ;;
                hcoll)
                    hcoll_info -a
                    shift 2
                    ;;
                mxm)
                    mxm_dump_config -f
                    shift 2
                    ;;
                ompi|hpcx)
                    ompi_info -a
                    shift 2
                    ;;
                sharp)
                    sharp_coll_dump_config -f
                    shift 2
                    ;;
                ucx)
                    ucx_info -f
                    shift 2
                    ;;
            esac
            exit 0
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
                    MODULES=${2//,/ }
                    Debug "MODULES=${MODULES}"
                    shift 2
                    ;;
            esac
            ;;
        -m|--mpis)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MPIS=(${2//,/ })
                    Debug "MPIS=(${MPIS[*]})"
                    shift 2
                    ;;
            esac
            ;;
        --mpi_vers)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MPI_VER=(${2//,/ })
                    Debug "MPI_VERS=(${MPI_VERS[*]})"
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
        -n|--nodes)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    if ! IsNumber "$2" ; then
                        Error ${EINTEGER} "NODES: $2 is not an integer."
                    fi
                    NODES="$2"
                    Debug "NODES=${NODES}"
                    shift 2
                    ;;
            esac
            ;;
        --ppn)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    if ! IsNumber "$2" ; then
                        Error ${EINTEGER} "PPN: $2 is not an integer."
                    fi
                    PPN="$2"
                    Debug "PPN=${PPN}"
                    shift 2
                    ;;
            esac
            ;;
        --threads)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    if ! IsNumber "$2" ; then
                        Error ${EINTEGER} "THREADS: $2 is not an integer."
                    fi
                    THREADS="$2"
                    Debug "THREADS=${THREADS}"
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
            Error ${EOPTARG} "Internal error."
            ;;
    esac
done

# Sanity checking
Sanitize

# Run
BuildJob
SubmitJob
