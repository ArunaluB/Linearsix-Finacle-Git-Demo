#!/bin/bash
#################################################################
# Name: validate_file_headers.sh
# Description: Validates file headers
# Date: 2026-02-16
# Author: DevOps Team
# Input: Changed files
# Output: Validation result
# Tables Used: None
# Calling Script: Jenkinsfile
#################################################################

set -euo pipefail

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

REQUIRED_FIELDS=(
    "Name:"
    "Description:"
    "Date:"
    "Author:"
    "Input:"
    "Output:"
    "Tables Used:"
    "Calling Script:"
)

# Get changed files
CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD | grep -E '\.(scr|sql|com|mrt)$' || true)

if [[ -z "${CHANGED_FILES}" ]]; then
    log "No files to validate"
    exit 0
fi

VALIDATION_FAILED=0

while IFS= read -r file; do
    log "Validating: ${file}"
    
    HEADER=$(head -n 20 "${file}" 2>/dev/null || echo "")
    
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! echo "${HEADER}" | grep -q "# ${field}"; then
            error "Missing field: ${field} in ${file}"
            VALIDATION_FAILED=1
        fi
    done
done <<< "${CHANGED_FILES}"

if [[ ${VALIDATION_FAILED} -eq 1 ]]; then
    exit 1
else
    log "✅ All files validated"
fi