#!/bin/bash
#################################################################
# Name: deploy_sql.sh
# Description: Deploys SQL files to Finacle database
# Date: 2026-02-15
# Author: DevOps Team
# Input: File path, environment, ticket number
# Output: Executed SQL changes
# Tables Used: Variable - depends on SQL content
# Calling Script: Jenkinsfile
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

# Backup existing SQL file if present
backup_sql_file() {
    log "Checking for existing SQL file..."
    
    local backup_script=$(cat << 'SQLBACKUPEOF'
#!/bin/bash
SQL_PATH="$1"
FILENAME="$2"
DATE_SUFFIX=$(date +%d%m%y)

SQL_FILE="${SQL_PATH}/sql/${FILENAME}"

if [[ -f "${SQL_FILE}" ]]; then
    BACKUP_NAME="${FILENAME}_backup_${DATE_SUFFIX}"
    cp -p "${SQL_FILE}" "${SQL_PATH}/sql/${BACKUP_NAME}"
    echo "SQL backup created: ${BACKUP_NAME}"
fi
SQLBACKUPEOF
    )
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${BASE_PATH} ${FILENAME}" <<< "${backup_script}"
}

# Copy SQL file to server
copy_sql_to_server() {
    log "Copying SQL file to server..."
    
    local patch_path="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
    local remote_sql_path="${patch_path}/cust/01/INFENG/sql/${FILENAME}"
    
    # Create directory if needed
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "mkdir -p ${patch_path}/cust/01/INFENG/sql"
    
    # Copy file
    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FILE_PATH}" "${FINACLE_USER}@${FINACLE_SERVER}:${remote_sql_path}"
    
    # Set permissions
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "chmod 775 ${remote_sql_path}"
    
    log "SQL file copied successfully"
}

# Execute SQL file
execute_sql() {
    log "Executing SQL file in database..."
    
    local patch_path="${PATCH_BASE}_${TICKET_NUMBER}/Localizations/patchArea"
    local sql_file="${patch_path}/cust/01/INFENG/sql/${FILENAME}"
    
    local sql_exec_script=$(cat << 'SQLEXECEOF'
#!/bin/bash
SQL_FILE="$1"
LOG_FILE="$2"

# Create log directory
mkdir -p $(dirname "${LOG_FILE}")

# Execute SQL using psq (Finacle's PostgreSQL client)
{
    echo "=== SQL Execution Started: $(date) ==="
    echo "File: ${SQL_FILE}"
    echo ""
    
    # Enter Finacle database session and execute
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
    
    local log_file="${SQL_LOG_DIR}/${FILENAME}_$(date +%Y%m%d_%H%M%S).log"
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${sql_file} ${log_file}" <<< "${sql_exec_script}"
    
    if [[ $? -eq 0 ]]; then
        log "SQL executed successfully"
        log "SQL log: ${log_file}"
    else
        error "SQL execution failed"
        return 1
    fi
}

# Main execution
main() {
    log "===== SQL DEPLOYMENT STARTED ====="
    log "File: ${FILENAME}"
    log "Environment: ${ENVIRONMENT}"
    log "Ticket: ${TICKET_NUMBER}"
    
    backup_sql_file || exit 1
    copy_sql_to_server || exit 1
    execute_sql || exit 1
    
    log "===== SQL DEPLOYMENT COMPLETED ====="
}

main "$@"
