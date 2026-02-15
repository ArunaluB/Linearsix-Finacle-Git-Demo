#!/bin/bash
#################################################################
# Name: cleanup_previous_deployment.sh
# Description: Cleans up previous deployment folders when switching branches/environments
# Date: 2026-02-15
# Author: DevOps Team
# Input: Current environment, ticket number
# Output: Cleaned server directories
# Tables Used: None
# Calling Script: Jenkinsfile (before deployment)
#################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="finadm"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
PATCH_BASE="/finutils/customizations"
FINAL_DELIVERY="/finutils/customizations_10225/Localizations/FinalDelivery"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Parse arguments
CURRENT_ENV=""
TICKET_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) CURRENT_ENV="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

log "===== CLEANING UP PREVIOUS DEPLOYMENT FOLDERS ====="
log "Current Environment: ${CURRENT_ENV}"
log "Ticket: ${TICKET_NUMBER}"

# Cleanup script to run on server
cleanup_script=$(cat << 'CLEANUPEOF'
#!/bin/bash
CURRENT_ENV="$1"
TICKET="$2"
PATCH_BASE="$3"

PATCH_PATH="${PATCH_BASE}_${TICKET}/Localizations/patchArea"

echo "Current Environment: ${CURRENT_ENV}"
echo "Patch Base: ${PATCH_PATH}"
echo ""

# Function to safely remove directory
safe_remove() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        echo "Removing: ${dir}"
        rm -rf "${dir}"
        echo "  ✓ Removed"
    else
        echo "  - Not found: ${dir}"
    fi
}

case ${CURRENT_ENV} in
    "DEV")
        echo "DEV Environment: Cleaning feature branch folders from previous runs"
        if [[ -d "${PATCH_PATH}/feature" ]]; then
            echo "Cleaning old feature branch folders..."
            rm -rf "${PATCH_PATH}/feature"/*
            echo "  ✓ Feature folders cleaned"
        fi
        ;;
        
    "QA")
        echo "QA Environment: Removing DEV feature folders"
        safe_remove "${PATCH_PATH}/feature"
        
        echo "Creating QA structure: ${PATCH_PATH}/DEV-${TICKET}"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/scripts"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/sql"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/com"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/mrt"
        chmod -R 775 "${PATCH_PATH}/DEV-${TICKET}"
        ;;
        
    "UAT")
        echo "UAT Environment: Removing DEV and QA folders"
        safe_remove "${PATCH_PATH}/feature"
        safe_remove "${PATCH_PATH}/DEV-${TICKET}-nirasha"
        safe_remove "${PATCH_PATH}/DEV-${TICKET}-harsha"
        safe_remove "${PATCH_PATH}/DEV-${TICKET}-chathuranga"
        
        # Keep only main DEV-${TICKET} folder for UAT
        echo "Creating UAT structure: ${PATCH_PATH}/DEV-${TICKET}"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/scripts"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/sql"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/com"
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}/mrt"
        chmod -R 775 "${PATCH_PATH}/DEV-${TICKET}"
        ;;
        
    "PRODUCTION")
        echo "PRODUCTION Environment: No patch structure needed"
        echo "Files will be copied directly to FinalDelivery"
        
        # Clean up all patch structures
        if [[ -d "${PATCH_PATH}" ]]; then
            echo "Removing entire patch structure (not needed in PRODUCTION)"
            rm -rf "${PATCH_PATH}"
        fi
        ;;
esac

echo ""
echo "Cleanup completed for ${CURRENT_ENV} environment"
echo ""
echo "Current directory structure:"
if [[ -d "${PATCH_PATH}" ]]; then
    ls -la "${PATCH_PATH}/" 2>/dev/null || echo "Empty"
else
    echo "No patch structure (PRODUCTION mode)"
fi
CLEANUPEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s ${CURRENT_ENV} ${TICKET_NUMBER} ${PATCH_BASE}" <<< "${cleanup_script}"

if [[ $? -eq 0 ]]; then
    log "Cleanup completed successfully"
else
    warning "Cleanup had some issues (may be normal if directories don't exist)"
fi

log "===== CLEANUP COMPLETED ====="
