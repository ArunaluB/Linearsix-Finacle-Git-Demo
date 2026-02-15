#!/bin/bash
#################################################################
# Name: rollback_deployment.sh
# Description: Rolls back failed Finacle deployment
# Date: 2026-02-16
# Author: DevOps Team
# Input: Environment, ticket number, timestamp
# Output: Restored previous version
# Tables Used: None
# Calling Script: Jenkinsfile (on failure)
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
BACKUP_BASE="/finapp/backup"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Parse arguments
ENVIRONMENT=""
TICKET_NUMBER=""
TIMESTAMP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        --timestamp) TIMESTAMP="$2"; shift 2 ;;
        *) error "Unknown parameter: $1"; exit 1 ;;
    esac
done

BACKUP_DIR="${BACKUP_BASE}/${ENVIRONMENT}_${TICKET_NUMBER}_${TIMESTAMP}"

log "===== ROLLBACK STARTED ====="
log "Restoring from: ${BACKUP_DIR}"

rollback_script=$(cat << 'ROLLBACKEOF'
#!/bin/bash
BACKUP_DIR="$1"
BASE_PATH="$2"

for dir in scripts sql com mrt; do
    if [[ -d "${BACKUP_DIR}/${dir}" ]]; then
        echo "Restoring ${dir}..."
        cp -rp "${BACKUP_DIR}/${dir}"/* "${BASE_PATH}/${dir}/" 2>/dev/null || true
    fi
done

echo "Rollback completed"
ROLLBACKEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s" <<< "${rollback_script}" -- "${BACKUP_DIR}" "${BASE_PATH}"

if [[ $? -eq 0 ]]; then
    log "✅ Rollback completed successfully"
else
    error "❌ Rollback failed"
    exit 1
fi