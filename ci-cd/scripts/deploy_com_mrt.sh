#!/bin/bash
#################################################################
# Name: deploy_com_mrt.sh
# Description: Deploys .com and .mrt files to Finacle
# Date: 2026-02-15
# Author: DevOps Team
# Input: File path, environment, ticket number
# Output: Executed COM/MRT files
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="finadm"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
BASE_PATH="/finapp/FIN/DEM/BE/Finacle/FC/app/cust/01/INFENG"
PATCH_BASE="/finutils/customizations"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2; }

# Parse arguments
FILE_PATH=""
ENVIRONMENT=""
TICKET_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --file) FILE_PATH="$2"; shift 2 ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        *) error "Unknown parameter: $1"; exit 1 ;;
    esac
done

FILENAME=$(basename "${FILE_PATH}")
EXTENSION="${FILENAME##*.}"

# Backup existing file
backup_file() {
    log "Creating backup of existing ${EXTENSION} file..."
    
    local backup_script=$(cat << 'COMBACKUPEOF'
#!/bin/bash
BASE_PATH="$1"
FILENAME="$2"
EXTENSION="$3"
DATE_SUFFIX=$(date +%d%m%y)

FILE_PATH="${BASE_PATH}/${EXTENSION}/${FILENAME}"

if [[ -f "${FILE_PATH}" ]]; then
    BACKUP_NAME="${FILENAME}_backup_${DATE_SUFFIX}"
    cp -p "${FILE_PATH}" "${BASE_PATH}/${EXTENSION}/${BACKUP_NAME}"
    echo "Backup created: ${BACKUP_NAME}"
fi
COMBACKUPEOF
    )
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${BASE_PATH} ${FILENAME} ${EXTENSION}" <<< "${backup_script}"
}

# Deploy COM/MRT file
deploy_file() {
    log "Deploying ${EXTENSION} file to patch area..."
    
    local patch_path="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
    local remote_path="${patch_path}/cust/01/INFENG/${EXTENSION}/${FILENAME}"
    
    # Create directory
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "mkdir -p ${patch_path}/cust/01/INFENG/${EXTENSION}"
    
    # Copy file
    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FILE_PATH}" "${FINACLE_USER}@${FINACLE_SERVER}:${remote_path}"
    
    # Set permissions
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "chmod 775 ${remote_path}"
    
    log "File deployed to patch area"
}

# Execute COM file
execute_com() {
    log "Executing ${FILENAME}..."
    
    local patch_path="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
    local com_path="${patch_path}/cust/01/INFENG/com"
    
    local exec_script=$(cat << 'COMEXECEOF'
#!/bin/bash
COM_PATH="$1"
FILENAME="$2"
FIN_INSTALL_ID="$3"

cd "${COM_PATH}" || exit 1

# Execute exectrusteduser.sh
exectrusteduser.sh << EXECCMD
. .profile
${FIN_INSTALL_ID}
./${FILENAME}
exit
EXECCMD

echo "COM execution completed"
COMEXECEOF
    )
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${com_path} ${FILENAME} ${FIN_INSTALL_ID:-FINDEM}" <<< "${exec_script}"
    
    if [[ $? -eq 0 ]]; then
        log "COM file executed successfully"
    else
        error "COM execution failed"
        return 1
    fi
}

# Main execution
main() {
    log "===== COM/MRT DEPLOYMENT STARTED ====="
    log "File: ${FILENAME}"
    log "Type: ${EXTENSION}"
    log "Environment: ${ENVIRONMENT}"
    
    backup_file || exit 1
    deploy_file || exit 1
    
    # Execute if it's a COM file
    if [[ "${EXTENSION}" == "com" ]]; then
        execute_com || exit 1
    fi
    
    log "===== COM/MRT DEPLOYMENT COMPLETED ====="
}

main "$@"
