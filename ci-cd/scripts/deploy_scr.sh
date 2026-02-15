#!/bin/bash
#################################################################
# Name: deploy_scr.sh
# Description: Deploys .scr files to Finacle server
# Date: 2026-02-16
# Author: DevOps Team
# Input: File path, environment, ticket number
# Output: Deployed .scr file
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

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

if [[ -z "${FILE_PATH}" ]] || [[ -z "${ENVIRONMENT}" ]] || [[ -z "${TICKET_NUMBER}" ]]; then
    error "Missing required parameters"
    exit 1
fi

FILENAME=$(basename "${FILE_PATH}")
CANONICAL_NAME="${FILENAME}"

log "===== SCR DEPLOYMENT STARTED ====="
log "File: ${FILENAME}"
log "Environment: ${ENVIRONMENT}"
log "Ticket: ${TICKET_NUMBER}"
log "SSH Key: ${SSH_KEY}"

# For DEV environment, add developer name
if [[ "${ENVIRONMENT}" == "DEV" ]] && [[ -n "${GIT_BRANCH:-}" ]]; then
    BRANCH_NAME="${GIT_BRANCH#origin/}"
    if [[ "${BRANCH_NAME}" =~ ^DEV-[0-9]+-(.+)$ ]]; then
        DEVELOPER_NAME="${BASH_REMATCH[1]}"
        FILENAME_BASE="${CANONICAL_NAME%.*}"
        FILENAME_EXT="${CANONICAL_NAME##*.}"
        FILENAME="${DEVELOPER_NAME}_${FILENAME_BASE}.${FILENAME_EXT}"
        log "DEV: Renamed to ${FILENAME}"
    fi
fi

# Determine paths
case "${ENVIRONMENT}" in
    "DEV")
        PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
    "QA"|"UAT")
        PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea/DEV-${TICKET_NUMBER}"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
    "PRODUCTION")
        PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/FinalDelivery"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
esac

# Copy file to server
log "Copying file to server..."
REMOTE_TEMP="/tmp/${FILENAME}.tmp"
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${FILE_PATH}" "${FINACLE_USER}@${FINACLE_SERVER}:${REMOTE_TEMP}"

if [[ $? -ne 0 ]]; then
    error "Failed to copy file"
    exit 1
fi

# Deploy on server
deploy_script=$(cat << 'DEPLOYEOF'
#!/bin/bash
PATCH_PATH="$1"
TARGET_PATH="$2"
FILENAME="$3"
CANONICAL_NAME="$4"
ENVIRONMENT="$5"
REMOTE_TEMP="/tmp/${FILENAME}.tmp"

echo "Creating patch directory: ${PATCH_PATH}"
mkdir -p "${PATCH_PATH}/cust/01/INFENG/scripts"

echo "Copying to patch area..."
cp "${REMOTE_TEMP}" "${PATCH_PATH}/cust/01/INFENG/scripts/${FILENAME}"
chmod 775 "${PATCH_PATH}/cust/01/INFENG/scripts/${FILENAME}"

# Create symlink
cd "${TARGET_PATH}" || exit 1

# Remove existing symlink or file
rm -f "${CANONICAL_NAME}"

# Create symlink
ln -fs "${PATCH_PATH}/cust/01/INFENG/scripts/${FILENAME}" "${CANONICAL_NAME}"

# Verify
if [[ -L "${CANONICAL_NAME}" ]]; then
    echo "Symlink created: ${CANONICAL_NAME} -> $(readlink ${CANONICAL_NAME})"
else
    echo "ERROR: Failed to create symlink" >&2
    exit 1
fi

# Cleanup
rm -f "${REMOTE_TEMP}"

echo "Deployment completed"
DEPLOYEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s" <<< "${deploy_script}" -- "${PATCH_PATH}" "${TARGET_PATH}" "${FILENAME}" "${CANONICAL_NAME}" "${ENVIRONMENT}"

if [[ $? -eq 0 ]]; then
    log "✅ SCR deployed successfully"
else
    error "❌ Deployment failed"
    exit 1
fi

log "===== SCR DEPLOYMENT COMPLETED ====="