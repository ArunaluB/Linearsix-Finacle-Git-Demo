#!/bin/bash
#################################################################
# Name: deploy_com_mrt.sh
# Description: Deploys .com and .mrt files to Finacle
# Date: 2026-02-16
# Author: DevOps Team
# Input: File path, environment, ticket number
# Output: Executed COM/MRT files
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="${FINACLE_USER:-finadm}"

# SSH key handling
if [[ -n "${SSH_KEY_FILE:-}" ]]; then
    SSH_KEY="${SSH_KEY_FILE}"
elif [[ -n "${SSH_KEY:-}" ]]; then
    SSH_KEY="${SSH_KEY}"
else
    SSH_KEY="${HOME}/.ssh/id_rsa"
fi

# Convert Windows path to Unix path for Git Bash
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    if command -v cygpath &> /dev/null; then
        SSH_KEY=$(cygpath -u "${SSH_KEY}")
    else
        SSH_KEY=$(echo "$SSH_KEY" | sed 's|\\|/|g' | sed 's|^C:|/c|' | sed 's|^D:|/d|')
    fi
fi

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

log "===== COM/MRT DEPLOYMENT STARTED ====="
log "File: ${FILENAME}"
log "Type: ${EXTENSION}"
log "Environment: ${ENVIRONMENT}"
log "Ticket: ${TICKET_NUMBER}"

# Copy file to server
PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
REMOTE_PATH="${PATCH_PATH}/cust/01/INFENG/${EXTENSION}/${FILENAME}"

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "mkdir -p ${PATCH_PATH}/cust/01/INFENG/${EXTENSION}"

scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FILE_PATH}" "${FINACLE_USER}@${FINACLE_SERVER}:${REMOTE_PATH}"

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "chmod 775 ${REMOTE_PATH}"

# Execute if COM file
if [[ "${EXTENSION}" == "com" ]]; then
    log "Executing COM file..."
    
    exec_script=$(cat << 'COMEXECEOF'
#!/bin/bash
COM_PATH="$1"
FILENAME="$2"

cd "${COM_PATH}" || exit 1

exectrusteduser.sh << EXECCMD
. .profile
FINDEM
./${FILENAME}
exit
EXECCMD

echo "COM execution completed"
COMEXECEOF
    )
    
    COM_PATH="${PATCH_PATH}/cust/01/INFENG/com"
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s" <<< "${exec_script}" -- "${COM_PATH}" "${FILENAME}"
fi

log "✅ COM/MRT deployment completed"