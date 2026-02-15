#!/bin/bash
#################################################################
# Name: restart_services.sh
# Description: Restarts Finacle services
# Date: 2026-02-16
# Author: DevOps Team
# Input: Finacle Installation ID
# Output: Service restart status
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

FIN_INSTALL_ID="${1:-FINDEM}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

FINLISTVAL_BIN="/finservices/FIN/DEM/finlistval/bin"
CORESESSION_BIN="/finservices/FIN/DEM/coresession/bin"

log "===== SERVICE RESTART STARTED ====="

# Restart finlistval
log "Restarting finlistval..."
cd "${FINLISTVAL_BIN}" || exit 1
./stop-finlistval${FIN_INSTALL_ID} || true
sleep 5
./start-finlistval${FIN_INSTALL_ID}

# Restart coresession
log "Restarting coresession..."
cd "${CORESESSION_BIN}" || exit 1
./stop-coresession${FIN_INSTALL_ID} || true
sleep 5
./start-coresession${FIN_INSTALL_ID}

log "✅ Services restarted"