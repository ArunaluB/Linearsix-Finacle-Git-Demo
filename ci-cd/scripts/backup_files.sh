#!/bin/bash
#################################################################
# Name: backup_files.sh
# Description: Creates comprehensive backup before deployment
# Date: 2026-02-15
# Author: DevOps Team
# Input: Environment, ticket number, timestamp
# Output: Backup files
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="finadm"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
BASE_PATH="/finapp/FIN/DEM/BE/Finacle/FC/app/cust/01/INFENG"
BACKUP_BASE="/finapp/backup"

# Color codes
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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
        *) shift ;;
    esac
done

log "Creating comprehensive backup for ${ENVIRONMENT}..."

backup_script=$(cat << 'BACKUPEOF'
#!/bin/bash
ENVIRONMENT="$1"
TICKET="$2"
TIMESTAMP="$3"
BASE_PATH="$4"
BACKUP_BASE="$5"

BACKUP_DIR="${BACKUP_BASE}/${ENVIRONMENT}_${TICKET}_${TIMESTAMP}"

mkdir -p "${BACKUP_DIR}/scripts"
mkdir -p "${BACKUP_DIR}/sql"
mkdir -p "${BACKUP_DIR}/com"
mkdir -p "${BACKUP_DIR}/mrt"

# Backup all directories
for dir in scripts sql com mrt; do
    if [[ -d "${BASE_PATH}/${dir}" ]]; then
        cp -rp "${BASE_PATH}/${dir}"/* "${BACKUP_DIR}/${dir}/" 2>/dev/null || true
    fi
done

# Create backup manifest
cat > "${BACKUP_DIR}/manifest.txt" << MANIFEST
Backup Created: $(date)
Environment: ${ENVIRONMENT}
Ticket: ${TICKET}
Timestamp: ${TIMESTAMP}
Source: ${BASE_PATH}
MANIFEST

echo "Backup created at: ${BACKUP_DIR}"
du -sh "${BACKUP_DIR}"
BACKUPEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s ${ENVIRONMENT} ${TICKET_NUMBER} ${TIMESTAMP} ${BASE_PATH} ${BACKUP_BASE}" <<< "${backup_script}"

log "Backup completed successfully"
