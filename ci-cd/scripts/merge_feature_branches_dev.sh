#!/bin/bash
#################################################################
# Name: merge_feature_branches_dev.sh
# Description: Merges all feature branches into DEV before QA deployment
# Date: 2026-02-15
# Author: DevOps Team
# Input: Ticket number
# Output: Merged DEV branch
# Tables Used: None
# Calling Script: Manual or before QA merge
#################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Parse arguments
TICKET_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --ticket) TICKET_NUMBER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "${TICKET_NUMBER}" ]]; then
    error "Ticket number is required (--ticket)"
    exit 1
fi

log "===== MERGING FEATURE BRANCHES TO DEV ====="
log "Ticket: ${TICKET_NUMBER}"

# Ensure we're on DEV branch
git checkout DEV
git pull origin DEV

# Find all feature branches for this ticket
FEATURE_BRANCHES=$(git branch -r | grep "origin/DEV-${TICKET_NUMBER}-" | sed 's/.*origin\///' | tr '\n' ' ')

if [[ -z "${FEATURE_BRANCHES}" ]]; then
    warning "No feature branches found for ticket ${TICKET_NUMBER}"
    exit 0
fi

log "Found feature branches:"
for branch in ${FEATURE_BRANCHES}; do
    echo "  - ${branch}"
done
echo ""

# Merge each feature branch
MERGE_FAILED=0
FAILED_BRANCHES=()

for branch in ${FEATURE_BRANCHES}; do
    log "Merging: ${branch}"
    
    if git merge "origin/${branch}" -m "Merge ${branch} into DEV for ticket ${TICKET_NUMBER}"; then
        log "✓ Successfully merged: ${branch}"
    else
        error "✗ Failed to merge: ${branch}"
        MERGE_FAILED=1
        FAILED_BRANCHES+=("${branch}")
        
        # Abort the merge
        git merge --abort
    fi
    
    echo ""
done

if [[ ${MERGE_FAILED} -eq 1 ]]; then
    error "Some branches failed to merge:"
    for failed in "${FAILED_BRANCHES[@]}"; do
        error "  - ${failed}"
    done
    error ""
    error "Please resolve conflicts manually and try again"
    exit 1
fi

log "All feature branches merged successfully into DEV"
log ""
log "Pushing merged DEV to remote..."

git push origin DEV

if [[ $? -eq 0 ]]; then
    log "✓ DEV branch pushed successfully"
else
    error "Failed to push DEV branch"
    exit 1
fi

log "===== FEATURE BRANCH MERGE COMPLETED ====="
log ""
info "Next steps:"
info "  1. Test the merged code in DEV environment"
info "  2. When ready, merge DEV to QA:"
info "     git checkout QA"
info "     git merge DEV"
info "     git push origin QA"
