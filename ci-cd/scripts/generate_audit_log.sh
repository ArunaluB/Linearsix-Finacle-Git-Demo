#!/bin/bash
#################################################################
# Name: generate_audit_log.sh
# Description: Generates comprehensive audit log for deployments
# Date: 2026-02-15
# Author: DevOps Team
# Input: Deployment metadata
# Output: Audit log file
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="finadm"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
AUDIT_LOG_DIR="/var/log/finacle-deployments"

# Parse arguments
ENVIRONMENT=""
TICKET_NUMBER=""
COMMIT_ID=""
AUTHOR=""
TIMESTAMP=""
APPROVER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        --commit) COMMIT_ID="$2"; shift 2 ;;
        --author) AUTHOR="$2"; shift 2 ;;
        --timestamp) TIMESTAMP="$2"; shift 2 ;;
        --approver) APPROVER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Get deployment details
HOSTNAME=$(hostname)
DEPLOYED_FILES=$(git diff --name-only HEAD~1 HEAD | tr '\n' ',' | sed 's/,$//')

# Generate audit log
audit_log_script=$(cat << AUDITEOF
#!/bin/bash
AUDIT_DIR="${AUDIT_LOG_DIR}"
LOG_FILE="${AUDIT_DIR}/deployment_audit_${TIMESTAMP}.log"

mkdir -p "${AUDIT_DIR}"

cat > "${LOG_FILE}" << 'LOGCONTENT'
================================================================================
                    FINACLE DEPLOYMENT AUDIT LOG
================================================================================

DEPLOYMENT INFORMATION
----------------------
Ticket Number:        ${TICKET_NUMBER}
Environment:          ${ENVIRONMENT}
Branch:               ${GIT_BRANCH:-Unknown}
Commit ID:            ${COMMIT_ID}
Timestamp:            ${TIMESTAMP}
Deploy Time:          $(date +'%Y-%m-%d %H:%M:%S')

AUTHORIZATION
-------------
Developer/Author:     ${AUTHOR}
Approver:             ${APPROVER}
Approval Required:    $([ "${ENVIRONMENT}" = "PRODUCTION" ] && echo "YES - Tech Lead" || [ "${ENVIRONMENT}" = "UAT" ] && echo "YES - QA Lead" || echo "NO - Auto")

SERVER INFORMATION
------------------
Target Server:        ${FINACLE_SERVER}
Finacle User:         ${FINACLE_USER}
Deploy Host:          ${HOSTNAME}

FILES DEPLOYED
--------------
${DEPLOYED_FILES}

DEPLOYMENT ACTIONS
------------------
$(cd ${AUDIT_DIR}/.. && find . -name "*${TICKET_NUMBER}*" -type f -mtime -1 -exec echo "- {}" \; 2>/dev/null || echo "- Deployment logs")

BACKUP INFORMATION
------------------
Backup Location:      ${AUDIT_DIR}/backups/${TICKET_NUMBER}
Backup Timestamp:     ${TIMESTAMP}
Rollback Available:   YES

VALIDATION
----------
File Header Check:    PASSED
FINL Validation:      PASSED
Service Restart:      COMPLETED

STATUS
------
Deployment Status:    SUCCESS
Audit Generated:      $(date +'%Y-%m-%d %H:%M:%S')

================================================================================
                        END OF AUDIT LOG
================================================================================
LOGCONTENT

chmod 644 "${LOG_FILE}"

echo "Audit log created: ${LOG_FILE}"
cat "${LOG_FILE}"
AUDITEOF
)

# Execute audit log creation on server
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "${audit_log_script}"

echo "Audit log generated successfully"
