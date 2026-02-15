#!/bin/bash
#################################################################
# Name: validate_file_headers.sh
# Description: Validates that all deployment files contain required header block
# Date: 2026-02-15
# Author: DevOps Team
# Input: Changed files from git
# Output: Validation result
# Tables Used: None
# Calling Script: Jenkinsfile
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

log "===== FILE HEADER VALIDATION STARTED ====="

# Required header fields
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
    log "No deployment files to validate"
    exit 0
fi

VALIDATION_FAILED=0
FAILED_FILES=()

# Validate each file
while IFS= read -r file; do
    if [[ ! -f "${file}" ]]; then
        warning "File not found: ${file}"
        continue
    fi
    
    log "Validating: ${file}"
    
    # Extract first 20 lines (header section)
    HEADER=$(head -n 20 "${file}")
    
    # Check for header block markers
    if ! echo "${HEADER}" | grep -q "#################################################################"; then
        error "Missing header block in: ${file}"
        VALIDATION_FAILED=1
        FAILED_FILES+=("${file}")
        continue
    fi
    
    # Check each required field
    MISSING_FIELDS=()
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! echo "${HEADER}" | grep -q "# ${field}"; then
            MISSING_FIELDS+=("${field}")
        fi
    done
    
    if [[ ${#MISSING_FIELDS[@]} -gt 0 ]]; then
        error "File ${file} is missing required fields:"
        for missing in "${MISSING_FIELDS[@]}"; do
            error "  - ${missing}"
        done
        VALIDATION_FAILED=1
        FAILED_FILES+=("${file}")
    else
        log "✓ Header validation passed: ${file}"
    fi
done <<< "${CHANGED_FILES}"

log "===== FILE HEADER VALIDATION COMPLETED ====="

if [[ ${VALIDATION_FAILED} -eq 1 ]]; then
    error "Header validation FAILED for the following files:"
    for failed_file in "${FAILED_FILES[@]}"; do
        error "  - ${failed_file}"
    done
    error ""
    error "All deployment files must contain the standard header block:"
    error ""
    error "#################################################################"
    error "# Name:"
    error "# Description:"
    error "# Date:"
    error "# Author:"
    error "# Input:"
    error "# Output:"
    error "# Tables Used:"
    error "# Calling Script:"
    error "#################################################################"
    error ""
    exit 1
else
    log "All files passed header validation"
    exit 0
fi
