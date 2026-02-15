#!/bin/bash
#################################################################
# Name: cleanup_dev_versions_qa.sh
# Description: Cleans up developer-named files in QA and creates canonical version
# Date: 2026-02-15
# Author: DevOps Team
# Input: Ticket number, file name
# Output: Single canonical file in QA
# Tables Used: None
# Calling Script: Jenkinsfile (QA stage)
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
TICKET_NUMBER=""
FILE_TYPE="scr"

while [[ $# -gt 0 ]]; do
    case $1 in
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        --type) FILE_TYPE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "${TICKET_NUMBER}" ]]; then
    error "Ticket number is required"
    exit 1
fi

# Validate SSH key exists
if [[ ! -f "${SSH_KEY}" ]]; then
    error "SSH key file not found: ${SSH_KEY}"
    exit 1
fi

log "===== QA CLEANUP: MERGING DEVELOPER VERSIONS ====="
log "Ticket: ${TICKET_NUMBER}"
log "File Type: ${FILE_TYPE}"
log "SSH Key: ${SSH_KEY}"

# Clean up developer versions in QA
cleanup_script=$(cat << 'CLEANUPEOF'
#!/bin/bash
BASE_PATH="$1"
FILE_TYPE="$2"
TICKET="$3"

case ${FILE_TYPE} in
    scr) DIR="scripts" ;;
    sql) DIR="sql" ;;
    com) DIR="com" ;;
    mrt) DIR="mrt" ;;
    *) DIR="scripts" ;;
esac

cd "${BASE_PATH}/${DIR}" || exit 1

echo "Current directory: $(pwd)"
echo ""
echo "Files before cleanup:"
ls -la *_*.${FILE_TYPE} 2>/dev/null || echo "No developer-named files found"
echo ""

# Find all developer-named files (format: developername_filename.ext)
for dev_file in *_*.${FILE_TYPE}; do
    if [[ -f "${dev_file}" ]]; then
        # Extract canonical name (remove developer prefix)
        # Example: nirasha_payoff.scr -> payoff.scr
        canonical_name=$(echo "${dev_file}" | sed 's/^[^_]*_//')
        
        echo "Processing: ${dev_file}"
        echo "  -> Canonical name will be: ${canonical_name}"
        
        # If canonical file doesn't exist, rename first developer version to canonical
        if [[ ! -f "${canonical_name}" ]]; then
            echo "  -> Creating canonical file from: ${dev_file}"
            cp "${dev_file}" "${canonical_name}"
            chmod 775 "${canonical_name}"
        fi
        
        # Delete developer version
        echo "  -> Deleting developer version: ${dev_file}"
        rm -f "${dev_file}"
        
        echo "  -> Done"
        echo ""
    fi
done

echo "=========================================="
echo "Cleanup completed. Final files:"
ls -la *.${FILE_TYPE} 2>/dev/null || echo "No files found"
echo "=========================================="

# Log the cleanup action
echo "QA Cleanup completed at $(date)" >> /var/log/finacle-deployments/qa_cleanup_${TICKET}.log
CLEANUPEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s ${BASE_PATH} ${FILE_TYPE} ${TICKET_NUMBER}" <<< "${cleanup_script}"

if [[ $? -eq 0 ]]; then
    log "QA cleanup completed successfully"
    log "All developer versions removed"
    log "Canonical files preserved"
else
    error "QA cleanup failed"
    exit 1
fi

log "===== QA CLEANUP COMPLETED ====="
