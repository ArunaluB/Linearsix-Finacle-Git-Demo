#!/bin/bash
#################################################################
# Name: restart_services.sh
# Description: Restarts Finacle services (finlistval and coresession)
# Date: 2026-02-15
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
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Service paths
FINLISTVAL_BIN="/finservices/FIN/DEM/finlistval/bin"
CORESESSION_BIN="/finservices/FIN/DEM/coresession/bin"

log "===== FINACLE SERVICE RESTART STARTED ====="
log "Installation ID: ${FIN_INSTALL_ID}"

# Restart finlistval service
log "Stopping finlistval service..."
cd "${FINLISTVAL_BIN}" || exit 1

./stop-finlistval${FIN_INSTALL_ID}

if [[ $? -eq 0 ]]; then
    log "finlistval stopped successfully"
else
    warning "finlistval stop had issues, continuing..."
fi

sleep 5

log "Starting finlistval service..."
./start-finlistval${FIN_INSTALL_ID}

if [[ $? -eq 0 ]]; then
    log "finlistval started successfully"
else
    error "Failed to start finlistval"
    exit 1
fi

sleep 10

# Restart coresession service
log "Stopping coresession service..."
cd "${CORESESSION_BIN}" || exit 1

./stop-coresession${FIN_INSTALL_ID}

if [[ $? -eq 0 ]]; then
    log "coresession stopped successfully"
else
    warning "coresession stop had issues, continuing..."
fi

sleep 5

log "Starting coresession service..."
./start-coresession${FIN_INSTALL_ID}

if [[ $? -eq 0 ]]; then
    log "coresession started successfully"
else
    error "Failed to start coresession"
    exit 1
fi

sleep 10

# Verify services are running
log "Verifying services..."

ps aux | grep -E "finlistval|coresession" | grep -v grep

log "===== FINACLE SERVICE RESTART COMPLETED ====="
