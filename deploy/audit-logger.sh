#!/bin/bash
# Tamper-evident audit logging compliant with CBSL requirements

AUDIT_DIR="/var/log/finacle"
mkdir -p "${AUDIT_DIR}" 2>/dev/null || true
CHRONICLE_LOG="${AUDIT_DIR}/deployment_chronicle.log"

log_critical() {
  local msg="${1}"
  local details="${2:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  echo "[CRITICAL] [${timestamp}] ${msg} | ${details}" | tee -a "${CHRONICLE_LOG}" >&2
}

log_error() {
  local msg="${1}"
  local details="${2:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  echo "[ERROR] [${timestamp}] ${msg} | ${details}" | tee -a "${CHRONICLE_LOG}" >&2
}

log_warning() {
  local msg="${1}"
  local details="${2:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  echo "[WARNING] [${timestamp}] ${msg} | ${details}" | tee -a "${CHRONICLE_LOG}" >&2
}

log_info() {
  local msg="${1}"
  local details="${2:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  echo "[INFO] [${timestamp}] ${msg} | ${details}" | tee -a "${CHRONICLE_LOG}" >&2
}

log_success() {
  local msg="${1}"
  local details="${2:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  echo "[SUCCESS] [${timestamp}] ${msg} | ${details}" | tee -a "${CHRONICLE_LOG}" >&2
}

# Cryptographic seal for audit integrity (SHA-256 chain)
seal_audit_log() {
  local log_file="${1}"
  if [[ -f "${log_file}" ]]; then
    sha256sum "${log_file}" >> "${log_file}.seal"
    chmod 440 "${log_file}" "${log_file}.seal"
  fi
}

# Validate environment
validate_environment() {
  local install_id="${1}"
  local env="${2}"
  local bank="${3}"
  
  # Check if environment is valid
  if [[ ! "${env}" =~ ^(DEV|QA|UAT|PRODUCTION)$ ]]; then
    log_critical "INVALID ENVIRONMENT" "Env=${env} not in allowed list"
    exit 1
  fi
  
  # Check if bank is valid
  case "${bank}" in
    SAMPATH|AFC|SIYAPATHA|PABC) ;;
    *) 
      log_critical "INVALID BANK" "Bank=${bank} not supported"
      exit 1
      ;;
  esac
  
  # Check if install ID is valid
  case "${install_id}" in
    FINDEM|FINAFC|FINSIYA|FINPABC) ;;
    *) 
      log_critical "INVALID INSTALL ID" "InstallID=${install_id} not mapped to bank"
      exit 1
      ;;
  esac
  
  log_info "ENVIRONMENT VALIDATED" "InstallID=${install_id}, Env=${env}, Bank=${bank}"
}

# Get SSH target for bank
get_ssh_target() {
  local bank="${1}"
  
  case "${bank}" in
    SAMPATH) echo "findem.linear6.com:22" ;;
    AFC) echo "afcdem.linear6.com:22" ;;
    SIYAPATHA) echo "siyadem.linear6.com:22" ;;
    PABC) echo "pabcdem.linear6.com:22" ;;
    *) echo "" ;;
  esac
}