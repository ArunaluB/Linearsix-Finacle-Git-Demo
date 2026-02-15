#!/bin/bash
#################################################################
# Name: verify_deployment.sh
# Description: Verifies deployment was successful
# Date: 2026-02-15
# Author: DevOps Team
# Input: Environment, ticket number
# Output: Verification result
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Configuration - SSH credentials from environment variables
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="${FINACLE_USER:-finadm}"
SSH_KEY="${SSH_KEY_FILE:-${SSH_KEY:-$HOME/.ssh/id_rsa}}"
BASE_PATH="/finapp/FIN/DEM/BE/Finacle/FC/app/cust/01/INFENG"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Parse arguments
ENVIRONMENT=""
TICKET_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Validate SSH key exists
if [[ ! -f "${SSH_KEY}" ]]; then
    error "SSH key file not found: ${SSH_KEY}"
    exit 1
fi

log "===== POST-DEPLOYMENT VERIFICATION STARTED ====="
log "SSH Key: ${SSH_KEY}"

verify_script=$(cat << 'VERIFYEOF'
#!/bin/bash
BASE_PATH="$1"

echo "Checking file permissions..."
find "${BASE_PATH}" -name "*.scr" -o -name "*.sql" -o -name "*.com" -o -name "*.mrt" | while read file; do
    perms=$(stat -c "%a" "${file}")
    if [[ "${perms}" != "775" ]]; then
        echo "WARNING: Incorrect permissions on ${file}: ${perms}"
    fi
done

echo "Checking symbolic links..."
find "${BASE_PATH}" -type l | while read link; do
    if [[ ! -e "${link}" ]]; then
        echo "ERROR: Broken symlink: ${link}"
        exit 1
    else
        echo "OK: ${link} -> $(readlink ${link})"
    fi
done

echo "Checking service status..."
ps aux | grep -E "finlistval|coresession" | grep -v grep || {
    echo "ERROR: Required services not running"
    exit 1
}

echo "Verification completed successfully"
VERIFYEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s ${BASE_PATH}" <<< "${verify_script}"

if [[ $? -eq 0 ]]; then
    log "Post-deployment verification PASSED"
    log "===== VERIFICATION COMPLETED ====="
    exit 0
else
    error "Post-deployment verification FAILED"
    exit 1
fi
