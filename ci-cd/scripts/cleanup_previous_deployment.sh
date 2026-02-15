#!/bin/bash
#################################################################
# Name: cleanup_previous_deployment.sh
# Description: Cleans up previous deployment folders
# Date: 2026-02-16
# Author: DevOps Team
# Input: Environment, ticket number
# Output: Cleaned directories
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

# Configuration
FINACLE_SERVER="findem.linear6.com"
FINACLE_USER="${FINACLE_USER:-finadm}"

if [[ -n "${SSH_KEY_FILE:-}" ]]; then
    SSH_KEY="${SSH_KEY_FILE}"
else
    SSH_KEY="${HOME}/.ssh/id_rsa"
fi

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    if command -v cygpath &> /dev/null; then
        SSH_KEY=$(cygpath -u "${SSH_KEY}")
    fi
fi

PATCH_BASE="/finutils/customizations"

# Parse arguments
CURRENT_ENV=""
TICKET_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --environment) CURRENT_ENV="$2"; shift 2 ;;
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

cleanup_script=$(cat << 'CLEANUPEOF'
#!/bin/bash
CURRENT_ENV="$1"
TICKET="$2"
PATCH_BASE="$3"

PATCH_PATH="${PATCH_BASE}_${TICKET}/Localizations/patchArea"

case ${CURRENT_ENV} in
    "DEV")
        rm -rf "${PATCH_PATH}/feature" 2>/dev/null || true
        ;;
    "QA")
        rm -rf "${PATCH_PATH}/feature" 2>/dev/null || true
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}"/{scripts,sql,com,mrt}
        ;;
    "UAT")
        rm -rf "${PATCH_PATH}/feature" 2>/dev/null || true
        rm -rf "${PATCH_PATH}/DEV-${TICKET}"-* 2>/dev/null || true
        mkdir -p "${PATCH_PATH}/DEV-${TICKET}"/{scripts,sql,com,mrt}
        ;;
    "PRODUCTION")
        rm -rf "${PATCH_PATH}" 2>/dev/null || true
        ;;
esac

echo "Cleanup completed for ${CURRENT_ENV}"
CLEANUPEOF
)

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no \
    "${FINACLE_USER}@${FINACLE_SERVER}" \
    "bash -s" <<< "${cleanup_script}" -- "${CURRENT_ENV}" "${TICKET_NUMBER}" "${PATCH_BASE}"

echo "✅ Cleanup completed"