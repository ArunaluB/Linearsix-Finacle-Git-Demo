#!/bin/bash
#################################################################
# Name: backup_files.sh
# Description: Creates comprehensive backup before deployment
# Date: 2026-02-16
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

# FIXED: Better SSH key handling for Windows
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
        # Manual conversion
        SSH_KEY=$(echo "$SSH_KEY" | sed 's|\\|/|g' | sed 's|^C:|/c|' | sed 's|^D:|/d|')
    fi
fi

BASE_PATH="/finapp/FIN/DEM/BE/Finacle/FC/app/cust/01/INFENG"
BACKUP_BASE="/finapp/backup"

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
TIMESTAMP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        --timestamp) TIMESTAMP="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "${ENVIRONMENT}" ]] || [[ -z "${TICKET_NUMBER}" ]] || [[ -z "${TIMESTAMP}" ]]; then
    error "Missing required parameters"
    exit 1
fi

log "Creating comprehensive backup for ${ENVIRONMENT}..."
log "SSH Key: ${SSH_KEY}"

backup_script=$(cat << 'BACKUPEOF'
#!/bin/bash
ENVIRONMENT="$1"
TICKET="$2"
TIMESTAMP="$3"
BASE_PATH="$4"
BACKUP_BASE="$5"

BACKUP_DIR="${BACKUP_BASE}/${ENVIRONMENT}_${TICKET}_${TIMESTAMP}"

echo "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}/scripts"
mkdir -p "${BACKUP_DIR}/sql"
mkdir -p "${BACKUP_DIR}/com"
mkdir -p "${BACKUP_DIR}/mrt"

# Backup all directories
for dir in scripts sql com mrt; do
    if [[ -d "${BASE_PATH}/${dir}" ]]; then
        echo "Backing up ${dir}..."
        cp -rp "${BASE_PATH}/${dir}"/* "${BACKUP_DIR}/${dir}/" 2>/dev/null || echo "  No files in ${dir}"
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
du -sh "${BACKUP_DIR}" 2>/dev/null || echo "Size: Unknown"
BACKUPEOF
)

# Execute backup on remote server
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    # Windows Git Bash
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s" <<< "${backup_script}" -- "${ENVIRONMENT}" "${TICKET_NUMBER}" "${TIMESTAMP}" "${BASE_PATH}" "${BACKUP_BASE}"
else
    # Linux/Unix
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${ENVIRONMENT} ${TICKET_NUMBER} ${TIMESTAMP} ${BASE_PATH} ${BACKUP_BASE}" <<< "${backup_script}"
fi

if [[ $? -eq 0 ]]; then
    log "✅ Backup completed successfully"
else
    error "❌ Backup failed"
    exit 1
fi