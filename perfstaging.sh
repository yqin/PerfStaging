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
VAL_COMPILERS=("gcc" "intel")
VAL_GNU_VERS=("4.8.5")
VAL_INTEL_VERS=("2018.1.163")

# MPIs
VAL_MPIS=("hpcx" "impi")
VAL_HPCX_VERS=("2.0.0" "2.1.0")
VAL_IMPI_VERS=("2018.1.163")

# MODES (PML or FABRIC)
VAL_HPCX_MODES=("ob1" "ucx" "yalla")
VAL_IMPI_MODES=("shm" "dapl" "tcp" "tmi" "ofa" "ofi")

# TLS
VAL_OB1_TLS=("oob" "openib")
VAL_UCX_TLS=("oob" "dc" "rc" "ud" "dc_x" "rc_x" "ud_x")
VAL_YALLA_TLS=("oob" "dc" "rc" "ud")


# Default values
DEBUG=${DEBUG:-0}
VERBOSE=${VERBOSE:-0}

ENV_VARS=( )
MODULES=( )

SBATCH=${SBATCH:-"sbatch"}
SLURM_TIME=${SLURM_TIME:-"30:0"}
SLURM_OPTS=${SLURM_OPTS:-""}
# Command/script to stage data/input for Slurm jobs
# e.g., --slurm_stage="ln -s ../input/* ./"
SLURM_STAGE=${SLURM_STAGE:-""}

CLUSTER=${CLUSTER:-""}

APP=${APP:-""}
APP_VER=${APP_VER:-""}
EXECUTABLE=${EXECUTABLE:-""}
INPUT=${INPUT:-""}

NODES=(${NODES[@]:-"1"})
PPNS=(${PPNS[@]:-"1"})
THREADS=(${THREADS[@]:-"1"})
PXT=${PXT:-"0"}

DEVICE=${DEVICE:-"mlx5_0"}
PORT=${PORT:-"1"}

# Arrays defined in environment have to be multi-value strings
# e.g., COMPILERS="intel gcc"
COMPILERS=(${COMPILERS[@]:-"intel"})
COMPILER_VERS=(${COMPILER_VERS[@]:-"2018.1.163"})

MPIS=(${MPIS[@]:-"hpcx"})
MPI_VERS=(${MPI_VERS[@]:-"2.1.0"})
# TODO: make it array?
MPI_OPTS=${MPI_OPTS:-""}
MAP_BY=${MAP_BY:-"socket"}
RANK_BY=${RANK_BY:-"core"}
BIND_TO=${BIND_TO:-"core"}
MODES=(${MODES[@]:-"ucx"})
MPIRUN=${MPIRUN:-"mpirun"}
TLS=(${TLS[@]:-"oob"})

#MXM_OPTS=${MXM_OPTS:-""}
#UCX_OPTS=${UCX_OPTS:-""}
#YALLA_OPTS=${YALLA_OPTS:-""}
#DAPL_OPTS=${DAPL_OPTS:-""}
#TMI_OPTS=${TMI_OPTS:-""}
#OFA_OPTS=${OFA_OPTS:-""}
#OFI_OPTS=${OFI_OPTS:-""}

HCOLL_OPTS=(${HCOLL_OPTS:-"0"})
KNEM_OPTS=(${KNEM_OPTS:-"0"})
SHARP_OPTS=(${SHARP_OPTS:-"0"})
TM_OPTS=(${TM_OPTS:-"0"})


# GLOBAL functions
# Print error message
function Error () {
    local EXIT="$1"
    shift
    local MSG="$@"
    echo "$(date +"%b %d %H:%M:%S") ERROR: "$MSG"" >&2
    exit $EXIT
}


# Print info message
function Info () {
    local MSG="$@"
    echo "$(date +"%b %d %H:%M:%S") INFO: "$MSG"" >&2
}


# Print verbose message
function Verbose () {
    local MSG="$@"
    if [[ ${VERBOSE} == 1 ]]; then
        echo "$(date +"%b %d %H:%M:%S") VERBOSE: "$MSG"" >&2
    fi  
}


# Print debug message
function Debug () {
    local MSG="$@"
    if [[ ${DEBUG} == 1 ]]; then
        echo "$(date +"%b %d %H:%M:%S") DEBUG: "$MSG"" >&2
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
        local TMP=""

        read -r -d '' TMP <<- EOS
module load ${MODULE}
EOS

        JOB_SCRIPT+=$'\n'
        JOB_SCRIPT+="${TMP}"

        Verbose "Loaded module \"${MODULE}\""
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

    if [[ -z "${EXECUTABLE}" ]]; then
        Error ${EOPTARG} "Application binary or executable not provided."
    fi

    if [[ -z "${CLUSTER}" ]]; then
        Error ${EOPTARG} "Cluster not provided."
    fi
}


# Load compiler module
function LoadCompiler () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    LoadModule "${COMPILER}/${COMPILER_VER}"

    Verbose "Loaded compiler \"${COMPILER}/${COMPILER_VER}\""
}


# Load MPI module
function LoadMPI () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    LoadModule "${MPI}/${MPI_VER}"

    Verbose "Loaded MPI \"${MPI}/${MPI_VER}\""
}


# Load application module
function LoadApp () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local APPMODULE=$( (module av -t) 2>&1 | grep -e "$(UtoL ${APP})/${APP_VER}-${MPI}-${MPI_VER}-${COMPILER}-${COMPILER_VER}" )

    Debug "Matched application module is: ${APPMODULE}"
    LoadModule "${APPMODULE}"

    Verbose "Loaded APP \"${APP}/${APP_VER}\""
}


# Load extra environment variables
function LoadEnvironment () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local TMP=""
    JOB_SCRIPT+=$'\n'

    read -r -d '' TMP <<- EOS
export OMP_NUM_THREADS=${THREAD}
EOS

    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+="${TMP}"

    for VAR in ${ENV_VARS[@]}; do
        read -r -d '' TMP <<- EOS
export ${VAR}
EOS

        JOB_SCRIPT+=$'\n'
        JOB_SCRIPT+="${TMP}"
    done

    Verbose "Exported environment variables \"OMP_NUM_THREADS=${THREAD} ${ENV_VARS[@]}\""
}


# Build common part of job script
function BuildJobCommon () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    # Header
    BuildJobHeader

    # Load compiler
    LoadCompiler

    # Load MPI
    LoadMPI

    # Load application module
    LoadApp

    # Load extra modules
    LoadModule "${MODULES[@]}"

    # Load extra environment variables
    LoadEnvironment

    # Body
    BuildJobBody
}


# Prepare job script header
function BuildJobHeader () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local TMP=""

    # Header
    read -r -d '' TMP <<- EOS
#!${SHELL} -l
#SBATCH --partition=${CLUSTER}
#SBATCH --nodes=${NODE}
#SBATCH --ntasks-per-node=${PPN}
#SBATCH --cpus-per-task=${THREAD}
#SBATCH --time=${SLURM_TIME}
#SBATCH --job-name=${JOB}
#SBATCH --output=${PWD}/${JOB}/${JOB}-%j.log
#SBATCH --workdir=${PWD}/${JOB}
EOS

    JOB_SCRIPT="${TMP}"

    if [[ -n ${SLURM_OPTS} ]]; then
        read -r -d '' TMP <<- EOS
#SBATCH ${SLURM_OPTS}
EOS

    JOB_SCRIPT+="${TMP}"
    fi

    read -r -d '' TMP <<- EOS
module purge
EOS

    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+="${TMP}"
}


# Prepare job script body
function BuildJobBody () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local TMP=""

    # TODO: fill ***TBD***
    read -r -d '' TMP <<- EOS
echo "DATE=\`date "+%F %T"\`"
echo "CLUSTER=${CLUSTER}"
echo "OS=\`cat /etc/redhat-release\`"
echo "KERNEL=\`uname -r\`"
echo "OFED=\`ofed_info -s | sed 's/://'\`"
echo "OPA=***TBD***"
echo "HCA_TYPE=\`ibstat ${DEVICE} | grep type | awk '{print \$3}'\`"
echo "HCA_FIRMWARE=\`ibstat ${DEVICE} | grep Firmware | awk '{print \$3}'\`"
echo "APP=${APP}"
echo "APP_VERSION=${APP_VER}"
echo "EXECUTABLE=${EXECUTABLE}"
echo "INPUT=${INPUT}"
echo "NODELIST=\${SLURM_NODELIST}"
echo "NODES=${NODE}"
echo "PPN=${PPN}"
echo "THREADS=${THREAD}"
echo "DEVICE=${DEVICE}"
echo "PORT=${PORT}"
echo "COMPILER=${COMPILER}"
echo "COMPILER_VERSION=${COMPILER_VER}"
echo "MPI=${MPI}"
echo "MPI_VERSION=${MPI_VER}"
echo "MODE=${MODE}"
echo "TL=${TL}"
echo "MPI_OPTS=${MPI_OPTS}"
echo "ENV_VARS=${ENV_VARS}"
echo "ENV=\`env\`"
EOS

    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+="${TMP}"
}


# Build HPCX job script
function BuildJobHPCX () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local TL=""
    local HCOLL_OPT=""
    local KNEM_OPT=""
    local SHARP_OPT=""
    local TM_OPT=""

    for TL in ${TLS[@]}; do

        Debug "TL=${TL}"

        local TEMP="VAL_$(LtoU ${MODE})_TLS[@]"
        if ! IsValid "${TL}" "${!TEMP}"; then
            Verbose "\"${TL}\" is not a valid TL for ${MODE}, pass"
            continue
        fi

        for HCOLL_OPT in ${HCOLL_OPTS[@]}; do

            Debug "HCOLL_OPT=${HCOLL_OPT}"

            for KNEM_OPT in ${KNEM_OPTS[@]}; do

                Debug "KNEM_OPT=${KNEM_OPT}"

                # PML is UCX and Transport is TM capable
                if [[ "${MODE}" == "ucx" && "${TL}" != "ud" && "${TL}" != "ud_x" ]]; then

                    for TM_OPT in ${TM_OPTS[@]}; do

                        Debug "TM_OPT=${TM_OPT}"

                        # Variable to store job script
                        local JOB=${APP}-${APP_VER}-${EXECUTABLE}.${CLUSTER}.${DEVICE}.$(printf "%03d" ${NODE})N.$(printf "%02d" ${PPN})P.$(printf "%02d" ${THREAD})T.${COMPILER}-${COMPILER_VER}.${MPI}-${MPI_VER}.${MODE}.${TL}.hcoll=${HCOLL_OPT}.knem=${KNEM_OPT}.tm=${TM_OPT}
                        local JOB_SCRIPT=""

                        # Build common part for the job script
                        BuildJobCommon

                        # Build MPIRUN command line for the job script
                        BuildJobHPCX_MPI_CMD

                        # Stage job
                        StageJob

                        # Show job script
                        ShowJob

                        # Submit job
                        SubmitJob

                    done # TM_OPT

                # PML is not UCX, or is UCX but using OOB or UD/UD_X Transport
                else

                    # Variable to store job script
                    local JOB=${APP}-${APP_VER}-${EXECUTABLE}.${CLUSTER}.${DEVICE}.$(printf "%03d" ${NODE})N.$(printf "%02d" ${PPN})P.$(printf "%02d" ${THREAD})T.${COMPILER}-${COMPILER_VER}.${MPI}-${MPI_VER}.${MODE}.${TL}.hcoll=${HCOLL_OPT}.knem=${KNEM_OPT}
                    local JOB_SCRIPT=""

                    # Build common part for the job script
                    BuildJobCommon

                    # Build MPIRUN command line for the job script
                    BuildJobHPCX_MPI_CMD

                    # Stage job
                    StageJob

                    # Show job script
                    ShowJob

                    # Submit job
                    SubmitJob

                fi

            done # KNEM_OPT

        done # HCOLL_OPT

    done # TL
}


# Build HPCX mpirun command line
function BuildJobHPCX_MPI_CMD () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local TMP=""
    local MPI_CMD="${MPIRUN}"

    # HPCX default options
    MPI_CMD+=" --display-map"
    MPI_CMD+=" --display-topo"
    MPI_CMD+=" --report-bindings"
    MPI_CMD+=" --map-by ${MAP_BY}:PE=${THREAD}"
    MPI_CMD+=" --rank-by ${RANK_BY}"
    MPI_CMD+=" --bind-to ${BIND_TO}"

    # PML
    MPI_CMD+=" -mca pml ${MODE}"

    if [[ "${TL}" != "oob" ]]; then

        if [[ "${MODE}" == "ob1" ]]; then
            MPI_CMD+=" -mca btl ${TL},vader,self"
        elif [[ "${MODE}" == "ucx" ]]; then
            MPI_CMD+=" -x UCX_TLS=${TL},shm,self"
        elif [[ "${MODE}" == "yalla" ]]; then
            MPI_CMD+=" -x MXM_TLS=${TL},shm,self"
        fi

    fi

    if [[ "${MODE}" == "ucx" ]]; then
        MPI_CMD+=" -x UCX_NET_DEVICES=${DEVICE}:${PORT}"
    elif [[ "${MODE}" == "yalla" ]]; then
        MPI_CMD+=" -x MXM_RDMA_PORTS=${DEVICE}:${PORT}"
    fi

    MPI_CMD+=" -mca btl_openib_if_include ${DEVICE}:${PORT}"

    # HCOLL
    MPI_CMD+=" -mca coll_fca_enable 0"
    if [[ "${HCOLL_OPT}" == 0 ]]; then
        MPI_CMD+=" -mca coll_hcoll_enable 0"
    elif [[ "${HCOLL_OPT}" == 1 ]]; then
        MPI_CMD+=" -mca coll_hcoll_enable 1"
        MPI_CMD+=" -x HCOLL_MAIN_IB=${DEVICE}:${PORT}"
    else
        MPI_CMD+=" -mca coll_hcoll_enable 1"
        MPI_CMD+=" -x HCOLL_MAIN_IB=${DEVICE}:${PORT}"
        MPI_CMD+=" -x ${HCOLL_OPT}"
    fi

    # KNEM
    if [[ "${KNEM_OPT}" == 0 ]]; then
        MPI_CMD+=" -mca btl_sm_use_knem 0"
    else
        MPI_CMD+=" -mca btl_sm_use_knem 1"
    fi

    # TM
    if [[ "${MODE}" == "ucx" && "${TL}" != "ud" && "${TL}" != "ud_x" ]]; then

        if [[ "${TM_OPT}" == 0 ]]; then
            MPI_CMD+=" -x UCX_DC_TM_ENABLE=0"
            MPI_CMD+=" -x UCX_RC_TM_ENABLE=0"
        elif [[ "${TM_OPT}" == 1 ]]; then
            MPI_CMD+=" -x UCX_RC_TM_ENABLE=1"
        else
            MPI_CMD+=" -x UCX_RC_TM_ENABLE=1"
            MPI_CMD+=" -x ${TM_OPT}"
        fi

    fi

    # Remaining options
    if [[ -n "${MPI_OPTS}" ]]; then
        MPI_CMD+=" ${MPI_OPTS}"
    fi

    # Application
    MPI_CMD+=" ${EXECUTABLE}"
    if [[ -n "${INPUT}" ]]; then
        MPI_CMD+=" ${INPUT}"
    fi

    read -r -d '' TMP <<- EOS
echo "MPIRUN_CMD=${MPI_CMD}"
echo
echo

echo Job started at \`date "+%F %T"\`
time ${MPI_CMD}
echo Job ended at \`date "+%F %T"\`
EOS

    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+="${TMP}"
}


# Build IMPI job script
function BuildJobIMPI () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    # Variable to store job script
    local JOB=${APP}-${APP_VER}-${EXECUTABLE}.${CLUSTER}.${DEVICE}.$(printf "%03d" ${NODE})N.$(printf "%02d" ${PPN})P.$(printf "%02d" ${THREAD})T.${COMPILER}-${COMPILER_VER}.${MPI}-${MPI_VER}.${MODE}
    local JOB_SCRIPT=""

    # Build common part for the job script
    BuildJobCommon

    # Build MPIRUN command line for the job script
    BuildJobIMPI_MPI_CMD

    # Stage job
    StageJob

    # Show job script
    ShowJob

    # Submit job
    SubmitJob
}


# Build IMPI mpirun command line
function BuildJobIMPI_MPI_CMD () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local TMP=""
    local MPI_CMD="${MPIRUN}"

    # IMPI default options
    MPI_CMD+=" -genv I_MPI_DEBUG 4"
    MPI_CMD+=" -genv I_MPI_FALLBACK 0"

    # FABRICS
    MPI_CMD+=" -genv I_MPI_FABRICS shm:${MODE}"
    if [[ "${MODE}" == "dapl" ]]; then
        MPI_CMD+=" -genv I_MPI_DAPL_UD 0"
        MPI_CMD+=" -genv I_MPI_DAPL_PROVIDER ofa-v2-${DEVICE}-${PORT}u"
    elif [[ "${MODE}" == "ofa" ]]; then
        MPI_CMD+=" -genv I_MPI_OFA_ADAPTER_NAME ${DEVICE}"
    fi

    # Remaining options
    if [[ -n "${MPI_OPTS}" ]]; then
        MPI_CMD+=" ${MPI_OPTS}"
    fi

    # Application
    MPI_CMD+=" ${EXECUTABLE}"
    if [[ -n "${INPUT}" ]]; then
        MPI_CMD+=" ${INPUT}"
    fi

    read -r -d '' TMP <<- EOS
echo "MPIRUN_CMD=${MPI_CMD}"
echo
echo

echo Job started at \`date "+%F %T"\`
time ${MPI_CMD}
echo Job ended at \`date "+%F %T"\`
EOS

    JOB_SCRIPT+=$'\n'
    JOB_SCRIPT+="${TMP}"
}


# Build job script
function BuildJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local NODE=
    local PPN=
    local THREAD=
    local COMPILER=""
    local COMPILER_VER=""
    local MPI=""
    local MPI_VER=""
    local MODE=""
    local TL=""

    # Permutate all valid combinations
    for NODE in ${NODES[@]}; do

        Debug "NODE=${NODE}"

        for PPN in ${PPNS[@]}; do

            Debug "PPN=${PPN}"

            for THREAD in ${THREADS[@]}; do

                Debug "THREAD=${THREAD}"

                if [[ ${PXT} != 0 && ${PXT} != $((${PPN} * ${THREAD})) ]]; then
                    Verbose "${PPN}*${THREAD}!=${PXT}, pass"
                    continue
                fi

                for COMPILER in ${COMPILERS[@]}; do

                    Debug "COMPILER=${COMPILER}"

                    if ! IsValid "${COMPILER}" "${VAL_COMPILERS[@]}"; then
                        Verbose "\"${COMPILER}\" is not a valid compiler, pass"
                        continue
                    fi

                    for COMPILER_VER in ${COMPILER_VERS[@]}; do

                        Debug "COMPILER_VER=${COMPILER_VER}"

                        local TEMP="VAL_$(LtoU ${COMPILER})_VERS[@]"
                        if ! IsValid "${COMPILER_VER}" "${!TEMP}"; then
                            Verbose "\"${COMPILER_VER}\" is not a valid version for ${COMPILER}, pass"
                            continue
                        fi

                        for MPI in ${MPIS[@]}; do

                            Debug "MPI=${MPI}"

                            if ! IsValid "${MPI}" "${VAL_MPIS[@]}"; then
                                Verbose "\"${MPI}\" is not a valid MPI, pass"
                                continue
                            fi

                            for MPI_VER in ${MPI_VERS[@]}; do

                                Debug "MPI_VER=${MPI_VER}"

                                local TEMP="VAL_$(LtoU ${MPI})_VERS[@]"
                                if ! IsValid "${MPI_VER}" "${!TEMP}"; then
                                    Verbose "\"${MPI_VER}\" is not a valid version for ${MPI}, pass"
                                    continue
                                fi

                                for MODE in ${MODES[@]}; do

                                    Debug "MODE=${MODE}"

                                    local TEMP="VAL_$(LtoU ${MPI})_MODES[@]"
                                    if ! IsValid "${MODE}" "${!TEMP}"; then
                                        Verbose "\"${MODE}\" is not a valid mode for ${MPI}, pass"
                                        continue
                                    fi

                                    # Branch based on MPI flavor
                                    if [[ $MPI == "hpcx" ]]; then
                                        BuildJobHPCX
                                    elif [[ $MPI == "impi" ]]; then
                                        BuildJobIMPI
                                    fi

                                done # MODE

                            done # MPI_VER

                        done # MPI

                    done # COMPILER_VER

                done # COMPILER

            done # THREAD

        done # PPN

    done # NODE
}


# Run staging script before job submission
function StageJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    # Create workdir for the job
    mkdir -p "${JOB}"
    Debug "Created directory \"${JOB}\""
    echo "${JOB_SCRIPT}" > "${JOB}/${JOB}.sh"
    Info "Built \"${JOB}\""

    # Perform staging process to prepare the job
    if [[ -n "${SLURM_STAGE}" ]]; then
        local CURRENT_DIR="${PWD}"

        cd "${JOB}"
        Debug "Running staging script from \"${JOB}\""
        local RETURN=$(eval "${SLURM_STAGE}")
        Debug "Staging script returned ($?): \"${RETURN}\""
        cd "${CURRENT_DIR}"
        Verbose "Staging script for \"${JOB}\" was run"
    fi
}


# Show job script
function ShowJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local LINE

    while read LINE; do
        Debug "${LINE}"
    done < "${JOB}/${JOB}.sh"
}


# Submit job script
function SubmitJob () {
    Debug "Calling ${FUNCNAME[0]}($@)"

    local JOBID=$(${SBATCH} "${JOB}/${JOB}.sh")

    Info "Submitted ${JOBID} \"${JOB}\""
}


function Usage () {
    echo "Usage: $0 [options]"
    echo
    echo "  General options:"
    echo "  -D,--debug          Debug mode"
    echo "  -h,--help,--usage   Help page (hcoll, impi, mxm, ompi, sharp, ucx)"
    echo "  -v,--verbose        Verbose mode"
    echo
    echo "  Application options:"
    echo "  -a,--app            Application"
    echo "     --app_ver        Application version"
    echo "  -b,--bin,--exe      Application binary or executable"
    echo "  -i,--input          Input data for benchmark"
    echo "     --cluster        Cluster"
    echo
    echo "  Slurm:"
    echo "     --slurm_time     Slurm time limit"
    echo "     --slurm_opts     Extra Slurm options"
    echo "     --slurm_stage    Command(s) or script(s) to stage data/input for Slurm jobs"
    echo
    echo "  Runtime environment:"
    echo "  -e,--env            Extra environment variables"
    echo "     --modules        Extra modules"
    echo "  -n,--nodes          # of Nodes"
    echo "     --ppn            # of processes/ranks per node"
    echo "     --threads        # of threads per process"
    echo "     --pxt            # of (ppn * threads), when provided, only run combinations when (ppn * threads == pxt)"
    echo
    echo "  Device:"
    echo "  -d,--device         Device"
    echo "  -p,--port           Port"
    echo
    echo "  Compiler options:"
    echo "  -c,--compilers      Compilers (gcc, intel, ...)"
    echo "     --compiler_vers  Compiler versions"
    echo
    echo "  MPI options:"
    echo "  -m,--mpis           MPIs (hpcx, impi, ...)"
    echo "     --mpi_vers       MPI versions"
    echo "     --mpirun         Redefine MPIRUN launcher (mpirun, oshrun, upcrun, ...)"
    echo "     --mpi_opts       Extra MPI options"
    echo "     --modes          Modes for MPI (pml or fabric, e.g., ob1, ucx, yalla, dapl, ofa, ...)"
    echo "     --map-by         OMPI --map-by option"
    echo "     --rank-by        OMPI --rank-by option"
    echo "     --bind-to        OMPI --bind-to option"
    echo "     --tls            TLs (openib, dc, rc, ud, dc_x, rc_x, ud_x"
    echo "     --hcoll          HCOLL options"
    echo "     --knem           KNEM options"
    echo "     --sharp          SHARP options"
    echo "     --tm             TM options"
}


# Retrieve command line options
CMD_OPTS=`getopt \
    -o a:b:c:Dd:e:h::i:m:n:p:v \
    -l app:,app_ver:,bin:,bind-to:,cluster:,compilers:,compiler_vers:,debug,device:,env:,exe:,hcoll::,help::,input:,knem::,map-by:,modes:,modules:,mpirun:,mpis:,mpi_vers:,mpi_opts:,nodes:,port:,ppn:,pxt:,rank-by:,sharp::,slurm_opts:,slurm_stage:,slurm_time:,threads:,tls:,tm::,usage::,verbose \
    -n "$0" -- "$@"`

if [[ $? != 0 ]]; then
    Error ${EOPTARG} "Failed to parse command line options."
fi

if [[ $# < 1 ]]; then
    Usage
    exit 0
else
    Info "$0 $@"
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
        -b|--bin|--exe)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    EXECUTABLE="$2"
                    Debug "EXECUTABLE=${EXECUTABLE}"
                    shift 2
                    ;;
            esac
            ;;
        --bind-to)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    BIND_TO="$2"
                    Debug "BIND_TO=${BIND_TO}"
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
                    COMPILERS=($(UtoL ${2//,/ }))
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
        -D|--debug)
            DEBUG=1
            VERBOSE=1
            shift
            ;;
        -d|--device)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    DEVICE="$2"
                    Debug "DEVICE=${DEVICE}"
                    shift 2
                    ;;
            esac
            ;;
        -e|--env)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    ENV_VARS=("${2//,/ }")
                    Debug "ENV_VARS=(${ENV_VARS[@]})"
                    shift 2
                    ;;
            esac
            ;;
        --hcoll)
            case "$2" in
                "")
                    HCOLL_OPTS=(1)
                    shift 2
                    ;;
                *)
                    HCOLL_OPTS=("${2//,/ }")
                    shift 2
                    ;;
            esac
            Debug "HCOLL_OPTS=(${HCOLL_OPTS[@]})"
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
                    mpirun --help
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
        --knem)
            case "$2" in
                "")
                    KNEM_OPTS=(1)
                    shift 2
                    ;;
                *)
                    KNEM_OPTS=("${2//,/ }")
                    shift 2
                    ;;
            esac
            Debug "KNEM_OPTS=(${KNEM_OPTS[@]})"
            ;;
        --map-by)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MAP_BY="$2"
                    Debug "MAP_BY=${MAP_BY}"
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
                    MODES=($(UtoL ${2//,/ }))
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
                    Debug "MODULES=(${MODULES[@]})"
                    shift 2
                    ;;
            esac
            ;;
        --mpirun)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    MPIRUN="$2"
                    Debug "MPIRUN=${MPIRUN}"
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
                    MPIS=($(UtoL ${2//,/ }))
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
                    NODES=(${2//,/ })
                    Debug "NODES=${NODES[@]}"
                    shift 2
                    ;;
            esac
            ;;
        -p|--port)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    PORT="$2"
                    Debug "PORT=${PORT}"
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
                    PPNS=(${2//,/ })
                    Debug "PPN=${PPNS[@]}"
                    shift 2
                    ;;
            esac
            ;;
        --pxt)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    PXT="$2"
                    Debug "PXT=${PXT}"
                    shift 2
                    ;;
            esac
            ;;
        --rank-by)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    RANK_BY="$2"
                    Debug "RANK_BY=${RANK_BY}"
                    shift 2
                    ;;
            esac
            ;;
        --sharp)
            case "$2" in
                "")
                    SHARP_OPTS=(1)
                    shift 2
                    ;;
                *)
                    SHARP=("${2//,/ }")
                    shift 2
                    ;;
            esac
            Debug "SHARP_OPTS=(${SHARP_OPTS[@]})"
            ;;
        --slurm_opts)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    SLURM_OPTS="$2"
                    Debug "SLURM_OPTS=${SLURM_OPTS}"
                    shift 2
                    ;;
            esac
            ;;
        --slurm_stage)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    SLURM_STAGE="$2"
                    Debug "SLURM_STAGE=${SLURM_STAGE}"
                    shift 2
                    ;;
            esac
            ;;
        --slurm_time)
            case "$2" in
                "")
                    shift 2
                    ;;
                *)
                    SLURM_TIME="$2"
                    Debug "SLURM_TIME=${SLURM_TIME}"
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
                    THREADS=(${2//,/ })
                    Debug "THREADS=${THREADS[@]}"
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
                    TLS=($(UtoL ${2//,/ }))
                    Debug "TLS=(${TLS[@]})"
                    shift 2
                    ;;
            esac
            ;;
        --tm)
            case "$2" in
                "")
                    TM_OPTS=(1)
                    shift 2
                    ;;
                *)
                    TM_OPTS=("${2//,/ }")
                    shift 2
                    ;;
            esac
            Debug "TM_OPTS=(${TM_OPTS[@]})"
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
