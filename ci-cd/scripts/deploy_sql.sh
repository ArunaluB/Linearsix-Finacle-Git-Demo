#!/bin/bash
#################################################################
# Name: deploy_sql.sh
# Description: Deploys SQL files to Finacle database
# Date: 2026-02-16
# Author: DevOps Team
# Input: File path, environment, ticket number
# Output: Executed SQL changes
# Tables Used: Variable
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
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
SQL_LOG_DIR="/var/log/finacle-sql"

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

log "===== SQL DEPLOYMENT STARTED ====="
log "File: ${FILENAME}"
log "Environment: ${ENVIRONMENT}"
log "Ticket: ${TICKET_NUMBER}"

# Copy SQL file to server
log "Copying SQL file to server..."

PATCH_PATH="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
REMOTE_SQL_PATH="${PATCH_PATH}/cust/01/INFENG/sql/${FILENAME}"

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "mkdir -p ${PATCH_PATH}/cust/01/INFENG/sql"

scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FILE_PATH}" "${FINACLE_USER}@${FINACLE_SERVER}:${REMOTE_SQL_PATH}"

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "chmod 775 ${REMOTE_SQL_PATH}"

# Execute SQL
log "Executing SQL in database..."

sql_exec_script=$(cat << 'SQLEXECEOF'
#!/bin/bash
SQL_FILE="$1"
LOG_DIR="$2"
FILENAME="$3"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/${FILENAME}_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

{
    echo "=== SQL Execution Started: $(date) ==="
    echo "File: ${SQL_FILE}"
    echo ""
    
    # Execute SQL using psq
    psq << SQLCMD
\i ${SQL_FILE}
\q
SQLCMD
    
    SQL_EXIT_CODE=$?
    
    echo ""
    echo "=== SQL Execution Completed: $(date) ==="
    echo "Exit Code: ${SQL_EXIT_CODE}"
    
    exit ${SQL_EXIT_CODE}
} 2>&1 | tee -a "${LOG_FILE}"
SQLEXECEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s" <<< "${sql_exec_script}" -- "${REMOTE_SQL_PATH}" "${SQL_LOG_DIR}" "${FILENAME}"

if [[ $? -eq 0 ]]; then
    log "✅ SQL executed successfully"
else
    error "❌ SQL execution failed"
    exit 1
fi

log "===== SQL DEPLOYMENT COMPLETED ====="