#!/bin/bash
#################################################################
# Name: run_finl.sh
# Description: Executes FINL validation
# Date: 2026-02-15
# Author: DevOps Team
# Input: Finacle Installation ID
# Output: FINL validation result
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

FIN_INSTALL_ID="${1:-FINDEM}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

log "===== FINL VALIDATION STARTED ====="
log "Installation ID: ${FIN_INSTALL_ID}"

# Execute FINL
log "Running FINL command..."

finl 2>&1 | tee /tmp/finl_output_$$.log

FINL_EXIT_CODE=${PIPESTATUS[0]}

if [[ ${FINL_EXIT_CODE} -eq 0 ]]; then
    log "FINL validation PASSED"
    log "===== FINL VALIDATION COMPLETED SUCCESSFULLY ====="
    exit 0
else
    error "FINL validation FAILED with exit code: ${FINL_EXIT_CODE}"
    error "Check log: /tmp/finl_output_$$.log"
    exit 1
fi
