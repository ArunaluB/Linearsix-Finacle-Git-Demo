#!/bin/bash
#################################################################
# Name: sync_branches_from_production.sh
# Description: Synchronizes all branches with PRODUCTION after prod deployment
# Date: 2026-02-15
# Author: DevOps Team
# Input: None (runs after PRODUCTION deployment)
# Output: Synchronized branches
# Tables Used: None
# Calling Script: Jenkinsfile (PRODUCTION stage)
#################################################################

set -euo pipefail

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

log "===== PRODUCTION BRANCH SYNCHRONIZATION STARTED ====="

# Fetch latest from origin
log "Fetching latest changes from origin..."
git fetch origin

# Get current PRODUCTION commit
PROD_COMMIT=$(git rev-parse origin/PRODUCTION)
log "PRODUCTION commit: ${PROD_COMMIT}"

# Branches to synchronize
BRANCHES_TO_SYNC=("DEV" "QA" "UAT")

for branch in "${BRANCHES_TO_SYNC[@]}"; do
    log "Synchronizing ${branch} with PRODUCTION..."
    
    # Checkout branch
    git checkout "${branch}" || {
        error "Failed to checkout ${branch}"
        continue
    }
    
    # Pull latest
    git pull origin "${branch}" || {
        warning "Pull had conflicts, attempting merge..."
    }
    
    # Merge PRODUCTION into branch
    if git merge origin/PRODUCTION -m "Auto-sync from PRODUCTION deployment [${PROD_COMMIT:0:8}]"; then
        log "Merged PRODUCTION into ${branch} successfully"
        
        # Push changes
        if git push origin "${branch}"; then
            log "Pushed ${branch} successfully"
        else
            error "Failed to push ${branch}"
        fi
    else
        error "Merge conflict in ${branch} - manual resolution required"
        git merge --abort
        
        # Send notification about conflict
        warning "Branch ${branch} has conflicts with PRODUCTION"
        warning "Manual merge required for ${branch}"
    fi
done

log "===== PRODUCTION BRANCH SYNCHRONIZATION COMPLETED ====="

# Return to PRODUCTION branch
git checkout PRODUCTION
