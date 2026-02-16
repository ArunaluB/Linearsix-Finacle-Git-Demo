#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# FINACLE ENTERPRISE DEPLOYMENT ORCHESTRATOR
# Version: 3.1.0
# Compliance: CBSL ITD Circular No. 04 of 2021 | PCI-DSS v4.0
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/audit-logger.sh"
source "${SCRIPT_DIR}/notify.sh"

# Mandatory parameters (validated upfront)
TICKET_NUMBER="${1:-}"
BRANCH_ENV="${2:-}"        # DEV|QA|UAT|PRODUCTION
INSTALL_ID="${3:-}"        # FINDEM|FINAFC|etc.
BANK_NAME="${4:-}"         # SAMPATH|AFC|SIYAPATHA|PABC
COMMIT_ID="${5:-}"
AUTHOR="${6:-}"
SSH_KEY_PATH="${7:-}"

# Exit immediately if required params missing
if [[ -z "${TICKET_NUMBER}" || -z "${BRANCH_ENV}" || -z "${INSTALL_ID}" || -z "${BANK_NAME}" || -z "${COMMIT_ID}" || -z "${AUTHOR}" || -z "${SSH_KEY_PATH}" ]]; then
  log_critical "MISSING REQUIRED PARAMETERS" "Ticket=${TICKET_NUMBER}, Env=${BRANCH_ENV}, InstallID=${INSTALL_ID}, Bank=${BANK_NAME}"
  exit 1
fi

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================
validate_environment "${INSTALL_ID}" "${BRANCH_ENV}" "${BANK_NAME}"

# Load bank-specific SSH target
SSH_TARGET=$(get_ssh_target "${BANK_NAME}")
if [[ -z "${SSH_TARGET}" ]]; then
  log_critical "INVALID BANK TARGET" "Bank=${BANK_NAME} not configured"
  exit 1
fi

# Parse SSH target
SSH_HOST=$(echo "${SSH_TARGET}" | cut -d: -f1)
SSH_PORT=$(echo "${SSH_TARGET}" | cut -d: -f2)

# ============================================================================
# DEPLOYMENT CONSTANTS
# ============================================================================
BASE_PATH="/finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/cust/01/INFENG"
PATCH_AREA="/finutils/customizations_${TICKET_NUMBER}/Localizations/patchArea"
FINAL_DELIVERY="/finutils/customizations_${TICKET_NUMBER}/Localizations/FinalDelivery"
BACKUP_PATH="/finapp/backup"
DATE_STAMP=$(date +%d%m%y)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
AUDIT_LOG="/var/log/finacle/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"

# File type routing matrix
declare -A FILE_ROUTING=(
  [".scr"]="${BASE_PATH}/scripts"
  [".sql"]="${BASE_PATH}/sql"
  [".com"]="${BASE_PATH}/com"
  [".mrt"]="${BASE_PATH}/mrt"
)

# ============================================================================
# PRE-DEPLOYMENT: SAFE BACKUP
# ============================================================================
log_info "PRE-DEPLOYMENT BACKUP" "Environment=${BRANCH_ENV}, Ticket=${TICKET_NUMBER}"

# Identify files to deploy from Git workspace
mapfile -t DEPLOY_FILES < <(find "${WORKSPACE}" -type f \( -name "*.scr" -o -name "*.sql" -o -name "*.com" -o -name "*.mrt" \) 2>/dev/null)

if [[ ${#DEPLOY_FILES[@]} -eq 0 ]]; then
  log_warning "NO DEPLOYABLE FILES FOUND" "Workspace=${WORKSPACE}"
  exit 0  # Graceful exit - no changes to deploy
fi

# Remote backup execution
BACKUP_COMMANDS=""
for file_path in "${DEPLOY_FILES[@]}"; do
  filename=$(basename "${file_path}")
  ext="${filename##*.}"
  target_dir="${FILE_ROUTING[.${ext}]}"
  live_path="${target_dir}/${filename}"
  
  # Build remote backup commands
  BACKUP_COMMANDS+="
    if [[ -f '${live_path}' ]]; then
      BACKUP_NAME='${filename}_safe_${DATE_STAMP}';
      if [[ '${BRANCH_ENV}' == 'QA' ]]; then
        mkdir -p ${BACKUP_PATH}/QA_safe_${DATE_STAMP};
        cp '${live_path}' '${BACKUP_PATH}/QA_safe_${DATE_STAMP}/\${BACKUP_NAME}' && \\
        mv '${live_path}' '${target_dir}/\${BACKUP_NAME}' && \\
        echo 'BACKUP: ${live_path} -> ${BACKUP_PATH}/QA_safe_${DATE_STAMP}/\${BACKUP_NAME}';
      else
        mv '${live_path}' '${target_dir}/\${BACKUP_NAME}' && \\
        echo 'BACKUP: ${live_path} -> ${target_dir}/\${BACKUP_NAME}';
      fi
    else
      echo 'NO EXISTING FILE TO BACKUP: ${live_path}';
    fi
  "
done

# Execute remote backup via SSH
ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
    -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${BACKUP_COMMANDS}'" \
    >> "${AUDIT_LOG}" 2>&1 || {
  log_critical "BACKUP FAILURE" "SSH backup commands failed"
  notify_failure "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "Backup failed before deployment"
  exit 1
}

# ============================================================================
# FILE DEPLOYMENT & SYMBOLIC LINKING
# ============================================================================
log_info "FILE DEPLOYMENT" "Files=${#DEPLOY_FILES[@]}, Target=${SSH_HOST}"

for file_path in "${DEPLOY_FILES[@]}"; do
  filename=$(basename "${file_path}")
  ext="${filename##*.}"
  target_dir="${FILE_ROUTING[.${ext}]}"
  
  # Determine deployment path based on environment
  if [[ "${BRANCH_ENV}" == "PRODUCTION" ]]; then
    deploy_path="${FINAL_DELIVERY}"
  else
    deploy_path="${PATCH_AREA}"
  fi
  
  # Create directory structure if needed
  mkdir -p "${deploy_path}/${ext}s" 2>/dev/null || true
  
  # Upload file via SCP
  scp -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
      -P "${SSH_PORT}" "${file_path}" \
      "finacle@${SSH_HOST}:${deploy_path}/${ext}s/" >> "${AUDIT_LOG}" 2>&1 || {
    log_critical "SCP FAILURE" "File=${filename}, Target=${deploy_path}"
    notify_failure "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "File transfer failed: ${filename}"
    exit 1
  }
  
  # Create symbolic link on remote server
  LINK_COMMAND="
    cd '${target_dir}' && \\
    ln -fs '${deploy_path}/${ext}s/${filename}' '${filename}' && \\
    chmod 775 '${filename}' && \\
    echo 'LINKED: ${filename} -> ${deploy_path}/${ext}s/${filename}'
  "
  
  ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
      -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${LINK_COMMAND}'" \
      >> "${AUDIT_LOG}" 2>&1 || {
    log_critical "LINK CREATION FAILED" "File=${filename}"
    notify_failure "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "Symbolic link failed for ${filename}"
    exit 1
  }
  
  log_success "DEPLOYED" "File=${filename}, Path=${deploy_path}/${ext}s"
done

# ============================================================================
# FINL VALIDATION & SERVICE RESTART
# ============================================================================
log_info "FINL VALIDATION" "InstallID=${INSTALL_ID}"

FINL_COMMAND="
  export FININSTALLID='${INSTALL_ID}';
  source /fincommon/ENVFILES/ENV_\${FININSTALLID}/PrepareEnv_\${FININSTALLID}.cfg 2>/dev/null || true;
  cd /finapp/FIN/\${FININSTALLID}/BE/Finacle/FC/app;
  ./finl 2>&1;
  FINL_EXIT=\$?;
  echo \"FINL_EXIT_CODE=\${FINL_EXIT}\";
  exit \${FINL_EXIT}
"

ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
    -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${FINL_COMMAND}'" \
    >> "${AUDIT_LOG}" 2>&1 || {
  log_critical "FINL VALIDATION FAILED" "Exit code non-zero"
  notify_failure "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "FINL validation failed - ROLLING BACK"
  "${SCRIPT_DIR}/rollback-finacle.sh" "${TICKET_NUMBER}" "${BRANCH_ENV}" "${INSTALL_ID}" "${BANK_NAME}" "${SSH_KEY_PATH}" "${AUDIT_LOG}"
  exit 1
}

# Controlled service restart sequence (critical for Finacle stability)
log_info "SERVICE RESTART SEQUENCE" "Environment=${BRANCH_ENV}"

RESTART_SCRIPT="${SCRIPT_DIR}/restart-services.sh"
ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
    -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -s" -- \
    "${INSTALL_ID}" "${BRANCH_ENV}" \
    < "${RESTART_SCRIPT}" >> "${AUDIT_LOG}" 2>&1 || {
  log_critical "SERVICE RESTART FAILED" "Critical services may be unstable"
  notify_failure "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "Service restart failed - MANUAL INTERVENTION REQUIRED"
  exit 1
}

# ============================================================================
# POST-DEPLOYMENT VERIFICATION
# ============================================================================
log_info "POST-DEPLOYMENT VERIFICATION" "Validating service health"

VERIFICATION_COMMAND="
  sleep 15;  # Allow services to stabilize
  ps -ef | grep -v grep | grep 'finlistval${INSTALL_ID}' | wc -l;
  ps -ef | grep -v grep | grep 'coresession${INSTALL_ID}' | wc -l
"

service_counts=$(ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_PATH}" \
    -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${VERIFICATION_COMMAND}'" 2>/dev/null || echo "0 0")

finlistval_count=$(echo "${service_counts}" | head -1)
coresession_count=$(echo "${service_counts}" | tail -1)

if [[ "${finlistval_count}" -lt 1 || "${coresession_count}" -lt 1 ]]; then
  log_critical "SERVICE VERIFICATION FAILED" "finlistval=${finlistval_count}, coresession=${coresession_count}"
  notify_failure "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "Services not running post-deployment - ROLLING BACK"
  "${SCRIPT_DIR}/rollback-finacle.sh" "${TICKET_NUMBER}" "${BRANCH_ENV}" "${INSTALL_ID}" "${BANK_NAME}" "${SSH_KEY_PATH}" "${AUDIT_LOG}"
  exit 1
fi

# ============================================================================
# AUDIT FINALIZATION & NOTIFICATION
# ============================================================================
log_success "DEPLOYMENT SUCCESSFUL" "Ticket=${TICKET_NUMBER}, Env=${BRANCH_ENV}, Bank=${BANK_NAME}, Files=${#DEPLOY_FILES[@]}"

# Immutable audit log archival (S3 integration placeholder)
if command -v aws &>/dev/null && [[ -n "${JENKINS_AUDIT_BUCKET:-}" ]]; then
  aws s3 cp "${AUDIT_LOG}" "s3://${JENKINS_AUDIT_BUCKET}/${BANK_NAME}/${BRANCH_ENV}/${TIMESTAMP}_${TICKET_NUMBER}.log" \
    --sse aws:kms --sse-kms-key-id alias/finacle-audit-key >> "${AUDIT_LOG}" 2>&1 || true
fi

# Success notification
notify_success "${TICKET_NUMBER}" "${BRANCH_ENV}" "${BANK_NAME}" "${COMMIT_ID}" "${AUTHOR}" "${#DEPLOY_FILES[@]}"

# Auto-sync PRODUCTION state to all branches (if production deployment)
if [[ "${BRANCH_ENV}" == "PRODUCTION" ]]; then
  log_info "PRODUCTION SYNC" "Syncing PRODUCTION state to lower environments"
  # Git operations handled by Jenkinsfile post-deployment
fi

exit 0