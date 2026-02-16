#!/bin/bash
set -euo pipefail

TICKET_NUMBER="${1:-}"
BRANCH_ENV="${2:-}"
INSTALL_ID="${3:-}"
BANK_NAME="${4:-}"
SSH_KEY_PATH="${5:-}"
AUDIT_LOG="${6:-/dev/null}"

DATE_STAMP=$(date +%d%m%y)
BASE_PATH="/finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/cust/01/INFENG"

# Identify rollback candidates (files with _safe_ suffix from today)
ROLLBACK_COMMAND="
  cd '${BASE_PATH}';
  find scripts sql com mrt -name '*_safe_${DATE_STAMP}' -type f 2>/dev/null | while read safe_file; do
    LIVE_NAME=\$(echo \$safe_file | sed 's/_safe_${DATE_STAMP}//');
    if [[ -f \"\$safe_file\" ]]; then
      mv \"\$safe_file\" \"\$LIVE_NAME\" && \\
      chmod 775 \"\$LIVE_NAME\" && \\
      echo \"ROLLED BACK: \$safe_file -> \$LIVE_NAME\";
    fi
  done
"

ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
    -p 22 "finacle@findem.linear6.com" "bash -c '${ROLLBACK_COMMAND}'" \
    >> "${AUDIT_LOG}" 2>&1 || {
  echo "CRITICAL: Rollback execution failed - manual intervention required" | tee -a "${AUDIT_LOG}" >&2
  exit 1
}

# Restart services after rollback
RESTART_SCRIPT="${SCRIPT_DIR}/restart-services.sh"
ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
    -p 22 "finacle@findem.linear6.com" "bash -s" -- \
    "${INSTALL_ID}" "${BRANCH_ENV}" \
    < "${RESTART_SCRIPT}" >> "${AUDIT_LOG}" 2>&1 || {
  echo "CRITICAL: Service restart after rollback failed" | tee -a "${AUDIT_LOG}" >&2
  exit 1
}

echo "ROLLBACK COMPLETED SUCCESSFULLY" | tee -a "${AUDIT_LOG}"
exit 0