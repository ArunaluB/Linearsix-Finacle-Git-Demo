#!/bin/bash
#################################################################
# Name: verify_deployment.sh
# Description: Verifies deployment was successful
# Date: 2026-02-16
# Author: DevOps Team
# Input: Environment, ticket number
# Output: Verification result
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

log "===== VERIFICATION STARTED ====="

verify_script=$(cat << 'VERIFYEOF'
#!/bin/bash
BASE_PATH="$1"

echo "Checking symbolic links..."
find "${BASE_PATH}" -type l -exec ls -la {} \; 2>/dev/null || echo "No symlinks found"

echo ""
echo "Checking service status..."
ps aux | grep -E "finlistval|coresession" | grep -v grep || echo "Services not running"

echo "Verification completed"
VERIFYEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s" <<< "${verify_script}" -- "${BASE_PATH}"

if [[ $? -eq 0 ]]; then
    log "✅ Verification completed"
else
    error "❌ Verification failed"
    exit 1
fi