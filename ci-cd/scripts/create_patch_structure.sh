#!/bin/bash
#################################################################
# Name: create_patch_structure.sh
# Description: Creates Finacle patch directory structure
# Date: 2026-02-15
# Author: DevOps Team
# Input: Ticket number, Install ID, Environment
# Output: Patch directory structure
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="finadm"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
PATCH_BASE="/finutils/customizations"
ENV_CONFIG_PATH="/fincommon/ENVFILES"

# Logging function
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
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ticket)
                TICKET_NUMBER="$2"
                shift 2
                ;;
            --install-id)
                FIN_INSTALL_ID="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            *)
                error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "${TICKET_NUMBER:-}" ]]; then
        error "Ticket number is required (--ticket)"
        exit 1
    fi
    
    if [[ -z "${FIN_INSTALL_ID:-}" ]]; then
        error "Finacle Install ID is required (--install-id)"
        exit 1
    fi
    
    if [[ -z "${ENVIRONMENT:-}" ]]; then
        error "Environment is required (--environment)"
        exit 1
    fi
}

# Load Finacle environment configuration
load_finacle_env() {
    log "Loading Finacle environment configuration for ${FIN_INSTALL_ID}..."
    
    local env_script=$(cat << 'ENVEOF'
#!/bin/bash
FIN_INSTALL_ID="$1"
ENV_FILE="/fincommon/ENVFILES/ENV_${FIN_INSTALL_ID}/PrepareEnv_${FIN_INSTALL_ID}.cfg"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: Environment file not found: ${ENV_FILE}" >&2
    exit 1
fi

while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue
    
    # Parse key=value pairs
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
        lvvar="${BASH_REMATCH[1]}"
        lvval="${BASH_REMATCH[2]}"
        
        # Export variables
        eval export "${lvvar}=${lvval}"
        echo "export ${lvvar}=${lvval}"
    fi
done < "${ENV_FILE}"

# Return environment variables as script
echo "echo 'ENVIRONMENT_LOADED=true'"
ENVEOF
    )
    
    # Execute on remote server and capture environment
    local env_vars=$(ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${FIN_INSTALL_ID}" <<< "${env_script}")
    
    if [[ $? -ne 0 ]]; then
        error "Failed to load Finacle environment"
        exit 1
    fi
    
    # Source environment variables locally
    eval "${env_vars}"
    
    log "Finacle environment loaded successfully"
}

# Create patch directory structure
create_patch_directories() {
    local patch_id="${TICKET_NUMBER}"
    local patch_path="${PATCH_BASE}_${patch_id}/Localizations/patchArea"
    
    log "Creating patch structure for ticket ${patch_id} in ${ENVIRONMENT}..."
    
    local create_script=$(cat << 'CREATEEOF'
#!/bin/bash
PATCH_PATH="$1"
ENVIRONMENT="$2"

# Create base patch directory
mkdir -p "${PATCH_PATH}"

# Create subdirectories
mkdir -p "${PATCH_PATH}/cust/01/INFENG/scripts"
mkdir -p "${PATCH_PATH}/cust/01/INFENG/sql"
mkdir -p "${PATCH_PATH}/cust/01/INFENG/com"
mkdir -p "${PATCH_PATH}/cust/01/INFENG/mrt"

# Create backup directory
mkdir -p "${PATCH_PATH}/backups"

# Create deployment metadata directory
mkdir -p "${PATCH_PATH}/metadata"

# Set permissions
chmod -R 775 "${PATCH_PATH}"

echo "Patch structure created successfully at: ${PATCH_PATH}"

# Create marker file
cat > "${PATCH_PATH}/metadata/deployment_info.txt" << INFO
Environment: ${ENVIRONMENT}
Created: $(date +'%Y-%m-%d %H:%M:%S')
Patch Path: ${PATCH_PATH}
INFO

ls -la "${PATCH_PATH}"
CREATEEOF
    )
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${patch_path} ${ENVIRONMENT}" <<< "${create_script}"
    
    if [[ $? -eq 0 ]]; then
        log "Patch directory structure created successfully"
    else
        error "Failed to create patch directory structure"
        exit 1
    fi
}

# Create feature branch directories for DEV environment
create_feature_branch_dirs() {
    if [[ "${ENVIRONMENT}" != "DEV" ]]; then
        return 0
    fi
    
    local patch_id="${TICKET_NUMBER}"
    local patch_path="${PATCH_BASE}_${patch_id}/Localizations/patchArea"
    
    log "Creating feature branch directories for DEV environment..."
    
    # Get list of feature branches from git
    local feature_branches=$(git branch -r | grep "origin/DEV-${patch_id}-" | sed 's/.*origin\///' | tr '\n' ' ')
    
    if [[ -z "${feature_branches}" ]]; then
        warning "No feature branches found for ticket ${patch_id}"
        return 0
    fi
    
    log "Found feature branches: ${feature_branches}"
    
    for branch in ${feature_branches}; do
        local developer_name=$(echo "${branch}" | awk -F'-' '{print $NF}')
        
        log "Creating directory for developer: ${developer_name}"
        
        local create_dev_script=$(cat << 'DEVEOF'
#!/bin/bash
PATCH_PATH="$1"
DEV_NAME="$2"

DEV_PATH="${PATCH_PATH}/feature/${DEV_NAME}"
mkdir -p "${DEV_PATH}/scripts"
mkdir -p "${DEV_PATH}/sql"
mkdir -p "${DEV_PATH}/com"
mkdir -p "${DEV_PATH}/mrt"

chmod -R 775 "${DEV_PATH}"

echo "Created feature directory for ${DEV_NAME}: ${DEV_PATH}"
echo ""
echo "Files will be named as: ${DEV_NAME}_filename.scr"
echo "Example: ${DEV_NAME}_payoff.scr"
DEVEOF
        )
        
        ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
            "${FINACLE_USER}@${FINACLE_SERVER}" \
            "bash -s ${patch_path} ${developer_name}" <<< "${create_dev_script}"
    done
    
    log "Feature branch directories created successfully"
}

# Main execution
main() {
    log "===== PATCH STRUCTURE CREATION STARTED ====="
    log "Ticket: ${TICKET_NUMBER}"
    log "Environment: ${ENVIRONMENT}"
    log "Install ID: ${FIN_INSTALL_ID}"
    
    parse_arguments "$@"
    load_finacle_env
    create_patch_directories
    
    # Create feature branch directories only for DEV
    if [[ "${ENVIRONMENT}" == "DEV" ]]; then
        create_feature_branch_dirs
    fi
    
    log "===== PATCH STRUCTURE CREATION COMPLETED ====="
}

# Execute main function
main "$@"
