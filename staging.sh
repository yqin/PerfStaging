#!/bin/bash

# GLOBAL settings
AUTHOR="Yong Qin (yongq@mellanox.com)"
VERSION="0.1"


# ERROR Codes
# 1 - command line option error
# 2 - not an integer
EOPTARG=1
EINTEGER=2


# Valid options
# Compilers
VAL_COMPILERS=("gnu" "intel")
VAL_GNU_VERS=("4.4.7")
VAL_INTEL_VERS=("2017.4.196")
# MPIs
VAL_MPIS=("hpcx" "impi")
VAL_HPCX_VERS=("1.9")
VAL_IMPI_VERS=("2017.3.196")
# MODES (PML or FABRIC)
VAL_HPCX_MODES=("ob1" "ucx" "yalla")
VAL_IMPI_MODES=("dapl" "ofa")
# TLS
VAL_OB1_TLS=("openib")
VAL_UCX_TLS=("rc" "rc_x" "ud_x" "dc_x")
VAL_YALLA_TLS=("rc" "ud")
VAL_DAPL_TLS=("ud")


# Default values
APP="OSU"
APP_VER="5.3.2"
BENCHMARK="osu_latency"
CLUSTER="DDDD"
COMPILERS=("intel")
COMPILER_VERS=("2017.4.196")
DEBUG=0
ENV_VARS=""
INPUT=""
MODES=("ob1")
MODULES=""
MPIS=("hpcx")
MPI_VERS=("1.9")
MPI_OPTS=""
MPI_CMD="mpirun"
NODES=(1)
PPNS=(1)
THREADS=(1)
TLS=("openib")
VERBOSE=0


# GLOBAL functions
# Print error message
function Error () {
    local EXIT="$1"
    shift
    local MSG="$@"
    echo "`date +"%b %d %H:%M:%S"` ERROR: "$MSG"" >&2
    exit $EXIT
}


# Print info message
function Info () {
    local MSG="$@"
    echo "`date +"%b %d %H:%M:%S"` INFO: "$MSG"" >&2
}


# Print verbose message
function Verbose () {
    local MSG="$@"
    if [[ ${VERBOSE} == 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` VERBOSE: "$MSG"" >&2
    fi  
}


# Print debug message
function Debug () {
    local MSG="$@"
    if [[ ${DEBUG} == 1 ]]; then
        echo "`date +"%b %d %H:%M:%S"` DEBUG: "$MSG"" >&2
    fi  
}


# Check if input value is a number or not
function IsNumber () {
    expr "$1" + 1 >/dev/null 2>&1
    return $?
}


# Validate if an element in array or not
function IsValid () {
    local e match="$1"
    shift

    for e; do
        [[ "$e" == "$match" ]] && return 0
    done

    return 1
}


# Convert lowercase to uppercase
function LtoU () {
    echo "$@" | tr a-z A-Z
}


# Convert uppercase to lowercase
function UtoL () {
    echo "$@" | tr A-Z a-z
}


# Load module(s)
function LoadModule () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local MODULE="$@"

    if [[ -n "${MODULE}" ]]; then
        cat >> "${JOB}" << EOF
module load ${MODULE}
EOF

        Verbose "Module \"${MODULE}\" loaded."
    fi
}


# Sanity checking to make sure all required information is provided
function Sanitize () {
    Debug "Calling ${FUNCNAME[0]}($@)"

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


# Load compiler module
function LoadCompiler () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    if [[ "${COMPILER}" == "gnu" ]]; then

        # No need to load module if system GCC is used
        if [[ "${COMPILER_VER}" == `gcc -v 2>&1 | awk 'END{print $3}'` ]]; then
            return
        fi

    fi

    if [[ "${COMPILER}" == "intel" ]]; then
        LoadModule "${COMPILER}/compiler/${COMPILER_VER}"
    else
        LoadModule "${COMPILER}/${COMPILER_VER}"
    fi

    Verbose "Compiler ${COMPILER}/${COMPILER_VER} loaded."
}


# Load MPI module
function LoadMPI () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    if [[ "${MPI}" == "hpcx" ]]; then

        if [[ "${COMPILER}" == "intel" ]]; then
            local SUFFIX=`echo ${COMPILER_VER} | awk -F. '{print $1}'`
            LoadModule "${MPI}-${MPI_VER}/icc-${SUFFIX}" 
        elif [[ "${COMPILER}" == "gnu" ]]; then
            LoadModule "${MPI}-${MPI_VER}/gcc"
        else
            LoadModule "${MPI}-${MPI_VER}"
        fi

    elif [[ "${MPI}" == "impi" ]]; then
        LoadModule "intel/${MPI}/${MPI_VER}"
    else
        LoadModule "${MPI}-${MPI_VER}"
    fi

    Verbose "MPI ${MPI}/${MPI_VER} loaded."
}


# Load application module
function LoadApp () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    LoadModule "`UtoL ${APP}`/${APP_VER}-${MPI}-${MPI_VER}-${COMPILER}-${COMPILER_VER}"

    Verbose "APP ${APP}/${APP_VER} loaded."
}


# Load extra environment variables
function LoadEnvironment () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    if [[ -n ${ENV_VARS} ]]; then
        cat >> "${JOB}" << EOF
export ${ENV_VARS}
EOF

        Verbose "Environment variables ${ENV_VARS} exported."
    fi
}


# Prepare job script header
function PrepareJobHead () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    cat > "${JOB}" << EOF
#!${SHELL}
module purge
EOF
}


# Prepare job script body
function PrepareJobBody () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    cat >> "${JOB}" << EOF

echo "DATE=\`date +%F %T\`"
echo "CLUSTER=${CLUSTER}"
echo "OS=\`cat /etc/redhat-release\`"
echo "KERNEL=\`uname -r\`"
echo "OFED=\`ofed_info|awk 'NR==1{print $1}'\`"
echo "APP=${APP}"
echo "APP_VERSION=${APP_VER}"
echo "BENCHMARK=${BENCHMARK}"
echo "COMPILER=${COMPILER}"
echo "COMPILER_VERSION=${COMPILER_VER}"
echo "MPI=${MPI}"
echo "MPI_VERSION=${MPI_VER}"
echo "MODE=${MODE}"
echo "TL=${TL}"
echo "MPI_OPTS=${MPI_OPTS}"
#echo "MPIRUN_CMD=${MPI_CMD}"
EOF

    BuildMPI_CMD
}


# Build MPIRUN command line
function BuildMPI_CMD () {
    Debug "Calling ${FUNCNAME[0]}($@)"
}


# Build job script
function BuildJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local COMPILER=""
    local COMPILER_VER=""
    local MPI=""
    local MPI_VER=""
    local MODE=""
    local TL=""
    local NODE=
    local PPN=
    local THREAD=

    # Permutate all valid combinations
    for NODE in ${NODES[@]}; do

        for PPN in ${PPNS[@]}; do

            for THREAD in ${THREADS[@]}; do

                for COMPILER in ${COMPILERS[@]}; do

                    if ! IsValid "${COMPILER}" "${VAL_COMPILERS[@]}"; then
                        Info "${COMPILER} is not a valid compiler, pass ..."
                        continue
                    fi

                    for COMPILER_VER in ${COMPILER_VERS[@]}; do

                        local TEMP="VAL_`LtoU ${COMPILER}`_VERS[@]"
                        if ! IsValid "${COMPILER_VER}" "${!TEMP}"; then
                            Info "${COMPILER_VER} is not a valid version for ${COMPILER}, pass ..."
                            continue
                        fi

                        for MPI in ${MPIS[@]}; do

                            if ! IsValid "${MPI}" "${VAL_MPIS[@]}"; then
                                Info "${MPI} is not a valid MPI, pass ..."
                                continue
                            fi

                            for MPI_VER in ${MPI_VERS[@]}; do

                                local TEMP="VAL_`LtoU ${MPI}`_VERS[@]"
                                if ! IsValid "${MPI_VER}" "${!TEMP}"; then
                                    Info "${MPI_VER} is not a valid version for ${MPI}, pass ..."
                                    continue
                                fi

                                for MODE in ${MODES[@]}; do

                                    local TEMP="VAL_`LtoU ${MPI}`_MODES[@]"
                                    if ! IsValid "${MODE}" "${!TEMP}"; then
                                        Info "${MODE} is not a valid mode for ${MPI}, pass ..."
                                        continue
                                    fi

                                    for TL in ${TLS[@]}; do

                                        local TEMP="VAL_`LtoU ${MODE}`_TLS[@]"
                                        if ! IsValid "${TL}" "${!TEMP}"; then
                                            Info "${TL} is not a valid TL for ${MODE}, pass ..."
                                            continue
                                        fi

                                        # Define job script name
                                        local JOB="${APP}-${APP_VER}-${BENCHMARK}.${CLUSTER}.`printf \"%03d\"${NODE}`N.`printf \"%02d\" ${PPN}`P.`printf \"%02d\"${THREADS}`T".${COMPILER}-${COMPILER_VER}.${MPI}-${MPI_VER}.${MODE}.${TL}
                                        local LOG="${JOB}.log"

                                        # Prepare job script header
                                        PrepareJobHead

                                        # Load compiler
                                        LoadCompiler

                                        # Load MPI
                                        LoadMPI

                                        # Load application module
                                        LoadApp

                                        # Load extra modules
                                        LoadModule "${MODULES}"

                                        # Load extra environment variables
                                        LoadEnvironment

                                        # Prepare job script body
                                        PrepareJobBody

                                        # Show job script
                                        ShowJob

                                        # Submit job
                                        SubmitJob

                                    done # TL

                                done # MODE

                            done # MPI_VER

                        done # MPI

                    done # COMPILER_VER

                done # COMPILER

            done # THREAD

        done # PPN

    done # NODE
}


# Show job script
function ShowJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local LINE

    while read LINE; do
        Debug "${LINE}"
    done < "${JOB}"
}


# Submit job script
function SubmitJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"
}


function Usage () {
    echo "Usage: $0 TBD"
    echo "  -a,--app            Application"
    echo "     --app_ver        Application version"
    echo "  -b,--bench          Benchmark"
    echo "     --cluster        Cluster"
    echo "  -c,--compilers      Compilers (gnu, intel, ...)"
    echo "     --compiler_vers  Compiler versions"
    echo "  -d,--debug          Debug mode"
    echo "  -e,--env            Environment variables"
    echo "  -h,--help,--usage   Help page (hcoll, impi, mxm, ompi, sharp, ucx)"
    echo "  -i,--input          Input data for benchmark"
    echo "     --modes          Modes for MPI (pml or fabirc, e.g., ob1, ucx, yalla, dapl, ofa, ...)"
    echo "     --modules        Extra modules"
    echo "  -m,--mpis           MPIs (hpcx, impi, ...)"
    echo "     --mpi_vers       MPI versions"
    echo "     --mpi_opts       Extra MPI options"
    echo "  -n,--nodes          # of Nodes"
    echo "     --ppn            # of processes per node"
    echo "     --threads        # of threads per process"
    echo "     --tls            TLS (rc, ud, rc_x, ud_x, dc_x, ...)"
    echo "  -v,--verbose        Verbose mode"
}


# Retrieve command line options
CMD_OPTS=`getopt \
    -o a:b:c:de:h::i:m:n:v \
    -l app:,app_ver:,bench:,cluster:,compilers:,compiler_vers:,debug,env:,help::,input:,modes:,modules:,mpis:,mpi_vers:,mpi_opts:,nodes:,ppn:,threads:,tls:,usage::,verbose \
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
                    COMPILERS=(`UtoL ${2//,/ }`)
                    Debug "COMPILERS=(${COMPILERS[@]})"
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
                    COMPILER_VERS=(${2//,/ })
                    Debug "COMPILER_VERS=(${COMPILER_VERS[@]})"
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
                impi)
                    mpirun --help
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
        --modes)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MODES=(`UtoL ${2//,/ }`)
                    Debug "MODES=(${MODES[@]})"
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
                    MPIS=(`UtoL ${2//,/ }`)
                    Debug "MPIS=(${MPIS[@]})"
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
                    MPI_VERS=(${2//,/ })
                    Debug "MPI_VERS=(${MPI_VERS[@]})"
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
        --tls)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    TLS=(`UtoL ${2//,/ }`)
                    Debug "TLS=(${TLS[@]})"
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

# Build and run jobs
BuildJob
