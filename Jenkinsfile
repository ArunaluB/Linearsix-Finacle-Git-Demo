#!/usr/bin/env groovy
/*
 * FINACLE ENTERPRISE CI/CD PIPELINE - AFC & MULTI-BANK SUPPORT
 * CBSL Compliant | Production Ready | Version 3.2.0
 */

pipeline {
    agent {
        label 'finacle-deploy-agent'
    }

    parameters {
        choice(
            name: 'BANK_TARGET',
            choices: ['SAMPATH', 'AFC', 'SIYAPATHA', 'PABC'],
            description: 'Target Financial Institution'
        )
        choice(
            name: 'DEPLOY_ENV',
            choices: ['DEV', 'QA', 'UAT', 'PRODUCTION'],
            description: 'Target Environment (governed by branch)'
        )
        string(
            name: 'TICKET_NUMBER',
            defaultValue: '10225',
            description: 'JIRA/ServiceNow Ticket Number (e.g., 10225)'
        )
        booleanParam(
            name: 'SKIP_VALIDATION',
            defaultValue: false,
            description: 'Skip pre-flight validation (EMERGENCY USE ONLY)'
        )
    }

    environment {
        // Jenkins Credentials (රහස්‍ය ගොනු)
        SSH_KEY_CRED = credentials('finadm')
        SMTP_CRED = credentials('finade-email-list')
        AUDIT_BUCKET = 'finacle-audit-logs-s3'
        
        // ✅ FIXED: Single-line ternary expression (no line breaks)
        INSTALL_ID = "${params.BANK_TARGET == 'SAMPATH' ? 'FINDEM' : (params.BANK_TARGET == 'AFC' ? 'FINAFC' : (params.BANK_TARGET == 'SIYAPATHA' ? 'FINSIYA' : 'FINPABC'))}"
        
        // ✅ FIXED: Correct BACKUP_PATH (not same as PATCH_AREA)
        BASE_PATH = "/finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/cust/01/INFENG"
        PATCH_AREA = "/finutils/customizations_${params.TICKET_NUMBER}/Localizations/patchArea"
        FINAL_DELIVERY = "/finutils/customizations_${params.TICKET_NUMBER}/Localizations/FinalDelivery"
        BACKUP_PATH = "/finapp/backup"
        
        // ✅ FIXED: Dynamic SSH target (not hardcoded to findem)
        SSH_HOST = "${params.BANK_TARGET == 'SAMPATH' ? 'findem.linear6.com' : (params.BANK_TARGET == 'AFC' ? 'findem.linear6.com' : (params.BANK_TARGET == 'SIYAPATHA' ? 'siyadem.linear6.com' : 'pabcdem.linear6.com'))}"
        SSH_PORT = '22'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '20'))
        disableConcurrentBuilds()
        ansiColor('xterm')
        skipStagesAfterUnstable()
    }

    stages {
        stage('SetBranchGovernance') {
            steps {
                script {
                    def currentBranch = sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
                    
                    def allowedBranches = [
                        'DEV': ['DEV-*'],
                        'QA': ['QA'],
                        'UAT': ['UAT'],
                        'PRODUCTION': ['PRODUCTION']
                    ]
                    
                    def valid = false
                    for (pattern in allowedBranches[params.DEPLOY_ENV]) {
                        if (currentBranch ==~ pattern || currentBranch == pattern) {
                            valid = true
                            break
                        }
                    }
                    
                    if (!valid) {
                        error "BRANCH GOVERNANCE VIOLATION: Branch '${currentBranch}' not permitted for ${params.DEPLOY_ENV} deployment"
                    }
                    
                    echo "✓ Branch governance validated: ${currentBranch} → ${params.DEPLOY_ENV}"
                }
            }
        }

        stage('Code Validation') {
            when { expression { !params.SKIP_VALIDATION } }
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    # Validate ticket format
                    if ! [[ "${TICKET_NUMBER}" =~ ^[0-9]+$ ]]; then
                        echo "ERROR: Invalid ticket number format" >&2
                        exit 1
                    fi
                    
                    # Validate file integrity
                    find . -name "*.scr" -o -name "*.sql" -o -name "*.com" -o -name "*.mrt" | while read file; do
                        if ! file "${file}" | grep -q "ASCII text"; then
                            echo "ERROR: Binary/non-text file detected: ${file}" >&2
                            exit 1
                        fi
                        if grep -q "password\\|secret\\|credential" "${file}" 2>/dev/null; then
                            echo "CRITICAL: Hardcoded secrets detected in ${file}" >&2
                            exit 1
                        fi
                    done
                    
                    echo "✓ Code validation passed"
                '''
            }
        }

        stage('ApprovalGate') {
            when {
                anyOf {
                    expression { params.DEPLOY_ENV == 'QA' }
                    expression { params.DEPLOY_ENV == 'UAT' }
                    expression { params.DEPLOY_ENV == 'PRODUCTION' }
                }
            }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    script {
                        def approvers = params.DEPLOY_ENV == 'UAT' ? ['qa-lead@linearsix.lk'] : 
                                       params.DEPLOY_ENV == 'PRODUCTION' ? ['tech-lead@linearsix.lk', 'ciso@linearsix.lk'] : 
                                       ['dev-manager@linearsix.lk']
                        
                        input message: "Approve ${params.DEPLOY_ENV} deployment for ${params.BANK_TARGET} (Ticket ${params.TICKET_NUMBER})?",
                               submitter: approvers.join(',')
                    }
                }
            }
        }

        stage('Patch Creation') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                    AUDIT_LOG="/tmp/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                    mkdir -p /tmp
                    
                    # Create patch structure
                    deploy/create-patch.sh \\
                        "${TICKET_NUMBER}" \\
                        "${INSTALL_ID}" \\
                        "${DEPLOY_ENV}" \\
                        "${AUDIT_LOG}"
                    
                    echo "✓ Patch structure created for ${BANK_TARGET} (${INSTALL_ID})"
                '''
            }
        }

        stage('Deployment') {
            steps {
                retry(3) {
                    sh '''
                        #!/bin/bash
                        set -euo pipefail
                        
                        COMMIT_ID=$(git rev-parse HEAD)
                        AUTHOR=$(git log -1 --pretty=format:'%an <%ae>')
                        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                        AUDIT_LOG="/tmp/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                        mkdir -p /tmp
                        
                        # Execute deployment orchestrator with dynamic SSH host
                        deploy/deploy-finacle.sh \\
                            "${TICKET_NUMBER}" \\
                            "${DEPLOY_ENV}" \\
                            "${INSTALL_ID}" \\
                            "${BANK_TARGET}" \\
                            "${COMMIT_ID}" \\
                            "${AUTHOR}" \\
                            "${SSH_KEY_CRED}" \\
                            "${SSH_HOST}" \\
                            "${SSH_PORT}"
                        
                        echo "✓ Deployment completed for ${BANK_TARGET}"
                    '''
                }
            }
        }

        stage('FINL Validation') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    FINL_COMMAND="
                      export FININSTALLID='${INSTALL_ID}';
                      source /fincommon/ENVFILES/ENV_\${FININSTALLID}/PrepareEnv_\${FININSTALLID}.cfg 2>/dev/null || true;
                      cd /finapp/FIN/\${FININSTALLID}/BE/Finacle/FC/app;
                      ./finl 2>&1;
                      FINL_EXIT=\$?;
                      echo 'FINL_EXIT_CODE=\${FINL_EXIT}';
                      exit \${FINL_EXIT}
                    "
                    
                    ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_CRED}" \\
                        -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${FINL_COMMAND}'" || {
                      echo "CRITICAL: FINL validation failed for ${BANK_TARGET}" >&2
                      exit 1
                    }
                    
                    echo "✓ FINL validation passed for ${BANK_TARGET}"
                '''
            }
        }

        stage('Service Restart') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    RESTART_COMMAND="
                      cd /finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app;
                      ./stop-finlistval${INSTALL_ID} && sleep 8;
                      ./stop-coresession${INSTALL_ID} && sleep 12;
                      ./start-coresession${INSTALL_ID} && sleep 15;
                      ./start-finlistval${INSTALL_ID}
                    "
                    
                    ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_CRED}" \\
                        -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${RESTART_COMMAND}'" || {
                      echo "CRITICAL: Service restart failed for ${BANK_TARGET}" >&2
                      exit 1
                    }
                    
                    echo "✓ Service restart completed for ${BANK_TARGET}"
                '''
            }
        }

        stage('Post Verification') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    sleep 20
                    
                    FINLISTVAL=$(ssh -o StrictHostKeyChecking=yes -i "${SSH_KEY_CRED}" \\
                        -p "${SSH_PORT}" "finacle@${SSH_HOST}" "ps -ef | grep -v grep | grep finlistval${INSTALL_ID} | wc -l" || echo 0)
                    CORESESSION=$(ssh -o StrictHostKeyChecking=yes -i "${SSH_KEY_CRED}" \\
                        -p "${SSH_PORT}" "finacle@${SSH_HOST}" "ps -ef | grep -v grep | grep coresession${INSTALL_ID} | wc -l" || echo 0)
                    
                    if [[ "${FINLISTVAL}" -lt 1 || "${CORESESSION}" -lt 1 ]]; then
                        echo "CRITICAL: Services not healthy post-deployment for ${BANK_TARGET}" >&2
                        echo "finlistval${INSTALL_ID}: ${FINLISTVAL} instances"
                        echo "coresession${INSTALL_ID}: ${CORESESSION} instances"
                        exit 1
                    fi
                    
                    echo "✓ Post-deployment verification passed for ${BANK_TARGET}"
                    echo "  - finlistval${INSTALL_ID}: running (${FINLISTVAL} instances)"
                    echo "  - coresession${INSTALL_ID}: running (${CORESESSION} instances)"
                '''
            }
        }

        stage('Audit Logging') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                    AUDIT_LOG="/tmp/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                    
                    echo "DEPLOYMENT COMPLETED: $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "${AUDIT_LOG}"
                    echo "BANK: ${BANK_TARGET}" >> "${AUDIT_LOG}"
                    echo "ENVIRONMENT: ${DEPLOY_ENV}" >> "${AUDIT_LOG}"
                    echo "TICKET: ${TICKET_NUMBER}" >> "${AUDIT_LOG}"
                    echo "INSTALL_ID: ${INSTALL_ID}" >> "${AUDIT_LOG}"
                    
                    # Archive audit log
                    cp "${AUDIT_LOG}" "${WORKSPACE}/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                    
                    echo "✓ Audit log created: deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                '''
            }
        }

        stage('Branch Sync') {
            when { expression { params.DEPLOY_ENV == 'PRODUCTION' } }
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    git config user.name "Finacle CI/CD Bot"
                    git config user.email "cicd@linearsix.lk"
                    git fetch origin
                    
                    for target in UAT QA DEV; do
                        git checkout "${target}" 2>/dev/null || git checkout -b "${target}" origin/"${target}"
                        git pull origin "${target}" || true
                        
                        if ! git merge --no-ff --no-edit origin/PRODUCTION 2>&1; then
                            git merge --abort
                            echo "CONFLICT: Merge conflict on ${target} branch - requires manual resolution" >&2
                            exit 1
                        fi
                        
                        git push origin "${target}"
                        echo "✓ Synced PRODUCTION → ${target}"
                    done
                '''
            }
        }
    }

    post {
        success {
            sh '''
                #!/bin/bash
                echo "✅ DEPLOYMENT SUCCESSFUL" 
                echo "Bank: ${BANK_TARGET}"
                echo "Environment: ${DEPLOY_ENV}"
                echo "Ticket: ${TICKET_NUMBER}"
                echo "Timestamp: $(date)"
            '''
            archiveArtifacts artifacts: 'deployment_audit_*.log', allowEmptyArchive: true
        }
        failure {
            sh '''
                #!/bin/bash
                echo "🚨 DEPLOYMENT FAILED"
                echo "Bank: ${BANK_TARGET}"
                echo "Environment: ${DEPLOY_ENV}"
                echo "Ticket: ${TICKET_NUMBER}"
                echo "Timestamp: $(date)"
                echo "Build URL: ${BUILD_URL}"
            '''
            archiveArtifacts artifacts: 'deployment_audit_*.log', allowEmptyArchive: true
        }
        always {
            cleanWs deleteDirs: true
        }
    }
}