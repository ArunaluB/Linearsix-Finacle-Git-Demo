#!/bin/bash
#################################################################
# Name: rollback_deployment.sh
# Description: Rolls back failed Finacle deployment
# Date: 2026-02-15
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

# Configuration - SSH credentials from environment variables
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="${FINACLE_USER:-finadm}"
SSH_KEY="${SSH_KEY_FILE:-${SSH_KEY:-$HOME/.ssh/id_rsa}}"
BASE_PATH="/finapp/FIN/DEM/BE/Finacle/FC/app/cust/01/INFENG"
ROLLBACK_LOG="/var/log/finacle-deployments/rollback.log"

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

if [[ -z "${ENVIRONMENT}" ]] || [[ -z "${TICKET_NUMBER}" ]]; then
    error "Missing required parameters"
    exit 1
fi

# Validate SSH key exists
if [[ ! -f "${SSH_KEY}" ]]; then
    error "SSH key file not found: ${SSH_KEY}"
    exit 1
fi

log "===== ROLLBACK STARTED ====="
log "Environment: ${ENVIRONMENT}"
log "Ticket: ${TICKET_NUMBER}"
log "Timestamp: ${TIMESTAMP}"
log "SSH Key: ${SSH_KEY}"

# Rollback script to execute on remote server
rollback_changes() {
    log "Rolling back changes on server..."
    
    local rollback_script=$(cat << 'ROLLBACKEOF'
#!/bin/bash
BASE_PATH="$1"
TICKET_NUMBER="$2"
DATE_SUFFIX=$(date +%d%m%y)

ROLLBACK_LOG="/var/log/finacle-deployments/rollback_${TICKET_NUMBER}_${DATE_SUFFIX}.log"

{
    echo "===== ROLLBACK EXECUTION STARTED ====="
    echo "Ticket: ${TICKET_NUMBER}"
    echo "Time: $(date)"
    echo ""
    
    # Find all backup files created today
    for dir in scripts sql com mrt; do
        echo "Processing directory: ${dir}"
        cd "${BASE_PATH}/${dir}" || continue
        
        # Find backup files
        for backup in *_safe_${DATE_SUFFIX}; do
            if [[ -f "${backup}" ]]; then
                original="${backup%_safe_${DATE_SUFFIX}}"
                
                echo "Restoring: ${backup} -> ${original}"
                
                # Remove current version
                rm -f "${original}"
                
                # Restore backup
                mv "${backup}" "${original}"
                
                # Set permissions
                chmod 775 "${original}"
                
                echo "Restored: ${original}"
            fi
        done
    done
    
    echo ""
    echo "===== ROLLBACK EXECUTION COMPLETED ====="
} 2>&1 | tee "${ROLLBACK_LOG}"

cat "${ROLLBACK_LOG}"
ROLLBACKEOF
    )
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        "bash -s ${BASE_PATH} ${TICKET_NUMBER}" <<< "${rollback_script}"
    
    if [[ $? -eq 0 ]]; then
        log "Rollback completed successfully"
    else
        error "Rollback had errors"
        return 1
    fi
}

# Re-run FINL after rollback
validate_after_rollback() {
    log "Running FINL validation after rollback..."
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        'bash /home/'"${FINACLE_USER}"'/scripts/run_finl.sh FINDEM'
    
    if [[ $? -eq 0 ]]; then
        log "FINL validation passed after rollback"
    else
        error "FINL validation failed after rollback - CRITICAL"
        return 1
    fi
}

# Restart services after rollback
restart_after_rollback() {
    log "Restarting services after rollback..."
    
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
        "${FINACLE_USER}@${FINACLE_SERVER}" \
        'bash /home/'"${FINACLE_USER}"'/scripts/restart_services.sh FINDEM'
    
    if [[ $? -eq 0 ]]; then
        log "Services restarted successfully"
    else
        error "Service restart failed - CRITICAL"
        return 1
    fi
}

# Main execution
main() {
    rollback_changes || exit 1
    validate_after_rollback || exit 1
    restart_after_rollback || exit 1
    
    log "===== ROLLBACK COMPLETED SUCCESSFULLY ====="
    
    # Generate rollback report
    cat << REPORT
ROLLBACK REPORT
================
Environment: ${ENVIRONMENT}
Ticket: ${TICKET_NUMBER}
Timestamp: ${TIMESTAMP}
Rollback Time: $(date +'%Y-%m-%d %H:%M:%S')
Status: SUCCESS

All changes have been reverted to previous version.
System is stable and operational.
REPORT
}

main "$@"
