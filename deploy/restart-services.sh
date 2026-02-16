#!/bin/bash
set -euo pipefail

INSTALL_ID="${1:-}"
BRANCH_ENV="${2:-}"

# Controlled restart sequence per Finacle best practices
restart_sequence() {
  echo "RESTARTING SERVICES FOR ${INSTALL_ID} (${BRANCH_ENV})"

  # Phase 1: Stop validation services
  echo "Stopping finlistval${INSTALL_ID}..."
  /finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/stop-finlistval${INSTALL_ID} || true
  sleep 8

  # Phase 2: Stop core session services
  echo "Stopping coresession${INSTALL_ID}..."
  /finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/stop-coresession${INSTALL_ID} || true
  sleep 12

  # Phase 3: Start core session services (critical dependency first)
  echo "Starting coresession${INSTALL_ID}..."
  /finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/start-coresession${INSTALL_ID}
  sleep 15

  # Phase 4: Start validation services
  echo "Starting finlistval${INSTALL_ID}..."
  /finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/start-finlistval${INSTALL_ID}
  sleep 10

  echo "SERVICE RESTART SEQUENCE COMPLETED"
}

# Execute restart with timeout protection (prevent hung processes)
timeout 120 bash -c restart_sequence || {
  echo "CRITICAL: Service restart timeout exceeded" >&2
  exit 1
}