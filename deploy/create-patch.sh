#!/bin/bash
set -euo pipefail

TICKET_NUMBER="${1:-}"
INSTALL_ID="${2:-}"
BRANCH_ENV="${3:-}"
AUDIT_LOG="${4:-/dev/null}"

if [[ -z "${TICKET_NUMBER}" || -z "${INSTALL_ID}" ]]; then
  echo "ERROR: Missing required parameters (TicketNumber, InstallID)" >&2
  exit 1
fi

# Load environment configuration
ENV_CONFIG="/fincommon/ENVFILES/ENV_${INSTALL_ID}/PrepareEnv_${INSTALL_ID}.cfg"
if [[ ! -f "${ENV_CONFIG}" ]]; then
  echo "ERROR: Environment config not found: ${ENV_CONFIG}" >&2
  exit 1
fi

# Determine patch path based on environment
if [[ "${BRANCH_ENV}" == "PRODUCTION" ]]; then
  PATCH_ROOT="/finutils/customizations_${TICKET_NUMBER}/Localizations/FinalDelivery"
else
  PATCH_ROOT="/finutils/customizations_${TICKET_NUMBER}/Localizations/patchArea"
fi

# Create idempotent directory structure
mkdir -p "${PATCH_ROOT}/scripts"
mkdir -p "${PATCH_ROOT}/sqls"
mkdir -p "${PATCH_ROOT}/coms"
mkdir -p "${PATCH_ROOT}/mrts"
mkdir -p "${PATCH_ROOT}/logs"

# Set strict permissions (banking requirement)
chmod 750 "${PATCH_ROOT}"
chmod 755 "${PATCH_ROOT}"/*/ 2>/dev/null || true

# Log creation
echo "PATCH STRUCTURE CREATED: ${PATCH_ROOT}" >> "${AUDIT_LOG}"
echo "TICKET: ${TICKET_NUMBER}" >> "${AUDIT_LOG}"
echo "INSTALL_ID: ${INSTALL_ID}" >> "${AUDIT_LOG}"
echo "ENVIRONMENT: ${BRANCH_ENV}" >> "${AUDIT_LOG}"

exit 0