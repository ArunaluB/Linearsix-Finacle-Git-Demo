#!/bin/bash
#################################################################
# Name: deploy_scr.sh
# Description: Deploys .scr files to Finacle server with safe backup and linking
# Date: 2026-02-15
# Author: DevOps Team
# Input: File path, environment, ticket number
# Output: Deployed and linked .scr file
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration - SSH credentials from environment variables
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="${FINACLE_USER:-finadm}"
SSH_KEY="${SSH_KEY_FILE:-${SSH_KEY:-$HOME/.ssh/id_rsa}}"
BASE_PATH="/finapp/FIN/DEM/BE/Finacle/FC/app/cust/01/INFENG"
PATCH_BASE="/finutils/customizations"
FINAL_DELIVERY="/finutils/customizations_10225/Localizations/FinalDelivery"
RETRY_COUNT=3
RETRY_DELAY=5

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Parse arguments
FILE_PATH=""
ENVIRONMENT=""
TICKET_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --file)
            FILE_PATH="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --ticket)
            TICKET_NUMBER="$2"
            shift 2
            ;;
        *)
            error "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Validate parameters
if [[ -z "${FILE_PATH}" ]] || [[ -z "${ENVIRONMENT}" ]] || [[ -z "${TICKET_NUMBER}" ]]; then
    error "Missing required parameters"
    error "Usage: $0 --file <file_path> --environment <env> --ticket <ticket_number>"
    exit 1
fi

# Validate SSH key exists
if [[ ! -f "${SSH_KEY}" ]]; then
    error "SSH key file not found: ${SSH_KEY}"
    error "Please set SSH_KEY_FILE environment variable"
    exit 1
fi

# Extract filename
FILENAME=$(basename "${FILE_PATH}")
CANONICAL_NAME="${FILENAME}"

# For DEV environment, add developer/branch name to filename
if [[ "${ENVIRONMENT}" == "DEV" ]]; then
    # Extract developer name from GIT_BRANCH environment variable or git command
    BRANCH_NAME="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")}"
    
    log "Branch Name: ${BRANCH_NAME}"
    
    # Remove 'origin/' prefix if present
    BRANCH_NAME="${BRANCH_NAME#origin/}"
    
    # Check if branch matches pattern: DEV-TICKET-developer
    if [[ "${BRANCH_NAME}" =~ ^DEV-[0-9]+-(.+)$ ]]; then
        DEVELOPER_NAME="${BASH_REMATCH[1]}"
        # Add developer name to filename: payoff.scr -> nirasha_payoff.scr
        FILENAME_BASE="${CANONICAL_NAME%.*}"
        FILENAME_EXT="${CANONICAL_NAME##*.}"
        FILENAME="${DEVELOPER_NAME}_${FILENAME_BASE}.${FILENAME_EXT}"
        
        log "DEV Environment: Renaming ${CANONICAL_NAME} to ${FILENAME} for developer ${DEVELOPER_NAME}"
    else
        log "DEV Environment: Not a feature branch (${BRANCH_NAME}), using canonical name"
    fi
fi

# Determine deployment paths based on environment
case "${ENVIRONMENT}" in
    "DEV")
        DEPLOY_MODE="FEATURE_BRANCH"
        PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
    "QA")
        DEPLOY_MODE="QA_PATCH"
        PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea/DEV-${TICKET_NUMBER}"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
    "UAT")
        DEPLOY_MODE="UAT_PATCH"
        PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea/DEV-${TICKET_NUMBER}"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
    "PRODUCTION")
        DEPLOY_MODE="FINAL_DELIVERY"
        FINAL_PATH="${FINAL_DELIVERY}"
        TARGET_PATH="${BASE_PATH}/scripts"
        ;;
    *)
        error "Unknown environment: ${ENVIRONMENT}"
        exit 1
        ;;
esac

log "===== SCR DEPLOYMENT STARTED ====="
log "File: ${FILENAME}"
log "Canonical Name: ${CANONICAL_NAME}"
log "Environment: ${ENVIRONMENT}"
log "Ticket: ${TICKET_NUMBER}"
log "Deploy Mode: ${DEPLOY_MODE}"
log "SSH Key: ${SSH_KEY}"
log "Finacle User: ${FINACLE_USER}"

# Function to execute remote command with retry
execute_remote_with_retry() {
    local command="$1"
    local attempt=1
    
    while [[ ${attempt} -le ${RETRY_COUNT} ]]; do
        log "Attempt ${attempt}/${RETRY_COUNT} to execute remote command"
        
        if ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
            "${FINACLE_USER}@${FINACLE_SERVER}" "${command}"; then
            return 0
        else
            warning "Attempt ${attempt} failed"
            if [[ ${attempt} -lt ${RETRY_COUNT} ]]; then
                log "Retrying in ${RETRY_DELAY} seconds..."
                sleep ${RETRY_DELAY}
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    error "All retry attempts failed"
    return 1
}

# Check if file exists and create backup
create_safe_backup() {
    # PRODUCTION doesn't need backup
    if [[ "${ENVIRONMENT}" == "PRODUCTION" ]]; then
        log "Backup not required for PRODUCTION environment"
        export BACKUP_CREATED=false
        return 0
    fi
    
    # DEV: Backup only when deploying CANONICAL file (not developer-named files)
    if [[ "${ENVIRONMENT}" == "DEV" ]] && [[ "${FILENAME}" != "${CANONICAL_NAME}" ]]; then
        log "DEV feature branch deployment - no backup needed for developer file"
        export BACKUP_CREATED=false
        return 0
    fi
    
    log "Checking if ${CANONICAL_NAME} exists in target location..."
    
    local backup_script=$(cat << 'BACKUPEOF'
#!/bin/bash
TARGET_PATH="$1"
FILENAME="$2"
ENVIRONMENT="$3"
DATE_SUFFIX=$(date +%d%m%y)

FILE_PATH="${TARGET_PATH}/${FILENAME}"

if [[ -f "${FILE_PATH}" ]]; then
    BACKUP_NAME="${FILENAME}_safe_${DATE_SUFFIX}"
    BACKUP_PATH="${TARGET_PATH}/${BACKUP_NAME}"
    
    echo "File exists. Creating backup: ${BACKUP_NAME}"
    
    # Create backup
    cp -p "${FILE_PATH}" "${BACKUP_PATH}"
    
    if [[ $? -eq 0 ]]; then
        echo "Backup created successfully: ${BACKUP_PATH}"
        echo "BACKUP_CREATED=true"
        echo "BACKUP_FILE=${BACKUP_NAME}"
    else
        echo "ERROR: Failed to create backup" >&2
        exit 1
    fi
else
    echo "File does not exist. This is a new API."
    echo "BACKUP_CREATED=false"
    echo "NEW_FILE=true"
fi
BACKUPEOF
    )
    
    local backup_result=$(execute_remote_with_retry "bash -s ${TARGET_PATH} ${CANONICAL_NAME} ${ENVIRONMENT}" <<< "${backup_script}")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to create backup"
        return 1
    fi
    
    echo "${backup_result}"
    
    # Parse backup result
    if echo "${backup_result}" | grep -q "BACKUP_CREATED=true"; then
        log "Backup created successfully"
        BACKUP_FILE=$(echo "${backup_result}" | grep "BACKUP_FILE=" | cut -d'=' -f2)
        export BACKUP_FILE
    elif echo "${backup_result}" | grep -q "NEW_FILE=true"; then
        log "This is a new file deployment"
        export NEW_FILE=true
    fi
    
    return 0
}

# Copy file to server
copy_file_to_server() {
    log "Copying ${FILENAME} to server..."
    
    local source_file="${FILE_PATH}"
    local remote_temp="/tmp/${FILENAME}.tmp"
    
    # Copy file to temp location on server
    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${source_file}" "${FINACLE_USER}@${FINACLE_SERVER}:${remote_temp}"
    
    if [[ $? -ne 0 ]]; then
        error "Failed to copy file to server"
        return 1
    fi
    
    log "File copied to server successfully"
    return 0
}

# Deploy based on mode
deploy_file() {
    log "Deploying file in ${DEPLOY_MODE} mode..."
    
    case "${DEPLOY_MODE}" in
        "FEATURE_BRANCH")
            deploy_feature_branch
            ;;
        "QA_PATCH")
            deploy_qa_patch
            ;;
        "UAT_PATCH")
            deploy_uat_patch
            ;;
        "FINAL_DELIVERY")
            deploy_to_final_delivery
            ;;
    esac
}

# Feature branch deployment for DEV (no backup, use patch area)
deploy_feature_branch() {
    log "Deploying to DEV feature branch via patch area..."
    
    local deploy_script=$(cat << 'DEVEOF'
#!/bin/bash
PATCH_PATH="$1"
TARGET_PATH="$2"
FILENAME="$3"
TEMP_FILE="/tmp/${FILENAME}.tmp"

# Create patch area
mkdir -p "${PATCH_PATH}/cust/01/INFENG/scripts"

# Copy to patch area
cp "${TEMP_FILE}" "${PATCH_PATH}/cust/01/INFENG/scripts/${FILENAME}"
chmod 775 "${PATCH_PATH}/cust/01/INFENG/scripts/${FILENAME}"

# Change to target directory
cd "${TARGET_PATH}" || exit 1

# Remove existing symlink if present
if [[ -L "${FILENAME}" ]]; then
    rm -f "${FILENAME}"
fi

# Create symbolic link from target to patch area
ln -fs "${PATCH_PATH}/cust/01/INFENG/scripts/${FILENAME}" "${FILENAME}"

# Verify link
if [[ -L "${FILENAME}" ]]; then
    echo "Symbolic link created successfully"
    ls -la "${FILENAME}"
    echo "Points to: $(readlink -f ${FILENAME})"
else
    echo "ERROR: Failed to create symbolic link" >&2
    exit 1
fi

# Clean up temp
rm -f "${TEMP_FILE}"

echo "DEV feature deployment completed"
DEVEOF
    )
    
    execute_remote_with_retry "bash -s ${PATCH_PATH} ${TARGET_PATH} ${FILENAME}" <<< "${deploy_script}"
    
    if [[ $? -eq 0 ]]; then
        log "DEV feature branch deployment completed"
    else
        error "DEV deployment failed"
        return 1
    fi
}

# QA deployment with patch structure (DEV-10225 folder)
deploy_qa_patch() {
    log "Deploying to QA patch structure (DEV-${TICKET_NUMBER})..."
    
    local deploy_script=$(cat << 'QAEOF'
#!/bin/bash
PATCH_PATH="$1"
TARGET_PATH="$2"
FILENAME="$3"
TEMP_FILE="/tmp/${FILENAME}.tmp"

# Copy to QA patch area: /patchArea/DEV-10225/scripts/
PATCH_FILE="${PATCH_PATH}/scripts/${FILENAME}"

mkdir -p "${PATCH_PATH}/scripts"
cp "${TEMP_FILE}" "${PATCH_FILE}"
chmod 775 "${PATCH_FILE}"

# Change to target directory
cd "${TARGET_PATH}" || exit 1

# Remove existing symlink if present
if [[ -L "${FILENAME}" ]]; then
    rm -f "${FILENAME}"
fi

# Create symbolic link
ln -fs "${PATCH_FILE}" "${FILENAME}"

# Verify link
if [[ -L "${FILENAME}" ]]; then
    echo "Symbolic link created successfully"
    ls -la "${FILENAME}"
else
    echo "ERROR: Failed to create symbolic link" >&2
    exit 1
fi

# Clean up temp
rm -f "${TEMP_FILE}"

echo "QA patch deployment completed"
QAEOF
    )
    
    execute_remote_with_retry "bash -s ${PATCH_PATH} ${TARGET_PATH} ${CANONICAL_NAME}" <<< "${deploy_script}"
    
    if [[ $? -eq 0 ]]; then
        log "QA patch deployment completed"
    else
        error "QA deployment failed"
        return 1
    fi
}

# UAT deployment (same as QA)
deploy_uat_patch() {
    log "Deploying to UAT patch structure (DEV-${TICKET_NUMBER})..."
    deploy_qa_patch
}

# Deployment to final delivery
deploy_to_final_delivery() {
    log "Deploying to final delivery location..."
    
    local deploy_script=$(cat << 'FINALEOF'
#!/bin/bash
FINAL_PATH="$1"
TARGET_PATH="$2"
FILENAME="$3"
TEMP_FILE="/tmp/${FILENAME}.tmp"

FINAL_FILE="${FINAL_PATH}/${FILENAME}"

# Ensure final delivery directory exists
mkdir -p "${FINAL_PATH}"

# Copy to final delivery
cp "${TEMP_FILE}" "${FINAL_FILE}"
chmod 775 "${FINAL_FILE}"

# Change to target directory
cd "${TARGET_PATH}" || exit 1

# Remove existing file/symlink
rm -f "${FILENAME}"

# Create symbolic link to final delivery
ln -fs "${FINAL_FILE}" "${FILENAME}"

# Verify
if [[ -L "${FILENAME}" ]]; then
    echo "Final delivery deployment completed"
    ls -la "${FILENAME}"
else
    echo "ERROR: Failed to create symbolic link" >&2
    exit 1
fi

# Clean up temp file
rm -f "${TEMP_FILE}"
FINALEOF
    )
    
    execute_remote_with_retry "bash -s ${FINAL_PATH} ${TARGET_PATH} ${CANONICAL_NAME}" <<< "${deploy_script}"
    
    if [[ $? -eq 0 ]]; then
        log "Final delivery deployment completed successfully"
    else
        error "Final delivery deployment failed"
        return 1
    fi
}

# Main execution
main() {
    # Create safe backup
    create_safe_backup || exit 1
    
    # Copy file to server
    copy_file_to_server || exit 1
    
    # Deploy file
    deploy_file || exit 1
    
    log "===== SCR DEPLOYMENT COMPLETED ====="
    
    # Return deployment info
    cat << INFO
DEPLOYMENT_INFO:
File: ${FILENAME}
Canonical: ${CANONICAL_NAME}
Environment: ${ENVIRONMENT}
Mode: ${DEPLOY_MODE}
Target: ${TARGET_PATH}/${CANONICAL_NAME}
Backup: ${BACKUP_FILE:-NONE}
Status: SUCCESS
INFO
}

main "$@"
