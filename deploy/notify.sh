#!/bin/bash
# TLS-secured email notifications with banking-grade encryption

notify_success() {
  local ticket="${1}"
  local env="${2}"
  local bank="${3}"
  local commit="${4}"
  local author="${5}"
  local file_count="${6}"
  
  local subject="✅ FINACLE DEPLOYMENT SUCCESS | ${bank} ${env} | Ticket ${ticket}"
  local body=$(cat <<EOF
Finacle Deployment Completed Successfully

Bank: ${bank}
Environment: ${env}
Ticket Number: ${ticket}
Commit ID: ${commit}
Author: ${author}
Files Deployed: ${file_count}
Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')

Deployment completed without errors. Services validated and operational.

-- 
Linearsix Finacle CI/CD System
CBSL Compliant | Audit ID: $(date +%Y%m%d%H%M%S)_${ticket}
EOF
)
  
  echo "${body}" | mail -s "${subject}" -S smtp-use-starttls \
    -S ssl-verify=strict -S smtp-auth=login \
    -S smtp="smtp.gmail.com:587" \
    -S from="finacle-cicd@linearsix.lk" \
    "operations@${bank,,}.lk" "audit@linearsix.lk" 2>/dev/null || true
}

notify_failure() {
  local ticket="${1}"
  local env="${2}"
  local bank="${3}"
  local reason="${4}"
  
  local subject="🚨 FINACLE DEPLOYMENT FAILED | ${bank} ${env} | Ticket ${ticket}"
  local body=$(cat <<EOF
CRITICAL: Finacle Deployment Failure

Bank: ${bank}
Environment: ${env}
Ticket Number: ${ticket}
Failure Reason: ${reason}
Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')

IMMEDIATE ACTION REQUIRED:
- Deployment halted at error stage
- Rollback executed automatically (if applicable)
- System state may be unstable
- Contact Finacle support team immediately

-- 
Linearsix Finacle CI/CD System
CBSL Compliant | Audit ID: $(date +%Y%m%d%H%M%S)_${ticket}_FAIL
EOF
)
  
  echo "${body}" | mail -s "${subject}" -S smtp-use-starttls \
    -S ssl-verify=strict -S smtp-auth=login \
    -S smtp="smtp.gmail.com:587" \
    -S from="finacle-cicd@linearsix.lk" \
    "operations@${bank,,}.lk" "support@linearsix.lk" "audit@linearsix.lk" 2>/dev/null || true
}