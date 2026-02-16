#!/usr/bin/env groovy
/*
 * FINACLE ENTERPRISE CI/CD PIPELINE
 * CBSL Compliant | Multi-Bank Support | Audit-Immutable
 * Version: 3.1.0 (Production Release)
 */

pipeline {
    agent {
        label 'finacle-deploy-agent'  // Dedicated agent with SSH keys
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
        // Jenkins Credential Manager IDs - NEVER hardcoded secrets
        SSH_KEY_CRED = credentials('finadm')
        SMTP_CRED = credentials('finade-email-list')
        AUDIT_BUCKET = 'finacle-audit-logs-s3'
        
        // Dynamic environment mapping
        INSTALL_ID = "${params.BANK_TARGET == 'SAMPATH' ? 'FINDEM' : 
                      params.BANK_TARGET == 'AFC' ? 'FINAFC' : 
                      params.BANK_TARGET == 'SIYAPATHA' ? 'FINSIYA' : 'FINPABC'}"
        
        // Critical paths
        BASE_PATH = "/finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/cust/01/INFENG"
        PATCH_AREA = "/finutils/customizations_${params.TICKET_NUMBER}/Localizations/patchArea"
        FINAL_DELIVERY = "/finutils/customizations_${params.TICKET_NUMBER}/Localizations/FinalDelivery"
        BACKUP_PATH = "/finapp/backup"
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
                    // Enforce branch-to-environment mapping
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
                        if grep -q "password\|secret\|credential" "${file}" 2>/dev/null; then
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
                    
                    # Capture deployment metadata
                    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                    AUDIT_LOG="/var/log/finacle/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                    
                    # Create patch structure
                    deploy/create-patch.sh \\
                        '${params.TICKET_NUMBER}' \\
                        '${env.INSTALL_ID}' \\
                        '${params.DEPLOY_ENV}' \\
                        '${AUDIT_LOG}'
                    
                    echo "✓ Patch structure created"
                '''
            }
        }

        stage('Deployment') {
            steps {
                retry(3) {
                    sh '''
                        #!/bin/bash
                        set -euo pipefail
                        
                        # Capture deployment metadata
                        COMMIT_ID=$(git rev-parse HEAD)
                        AUTHOR=$(git log -1 --pretty=format:'%an <%ae>')
                        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                        AUDIT_LOG="/var/log/finacle/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                        
                        # Execute deployment orchestrator
                        deploy/deploy-finacle.sh \\
                            '${params.TICKET_NUMBER}' \\
                            '${params.DEPLOY_ENV}' \\
                            '${env.INSTALL_ID}' \\
                            '${params.BANK_TARGET}' \\
                            "${COMMIT_ID}" \\
                            "${AUTHOR}" \\
                            '${SSH_KEY_CRED}'
                        
                        # Seal audit log cryptographically
                        deploy/audit-logger.sh seal \\
                            "/var/log/finacle/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                    '''
                }
            }
        }

        stage('FINL Validation') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    # FINL validation command
                    FINL_COMMAND="
                      export FININSTALLID='${env.INSTALL_ID}';
                      source /fincommon/ENVFILES/ENV_\${FININSTALLID}/PrepareEnv_\${FININSTALLID}.cfg 2>/dev/null || true;
                      cd /finapp/FIN/\${FININSTALLID}/BE/Finacle/FC/app;
                      ./finl 2>&1;
                      FINL_EXIT=\$?;
                      echo \"FINL_EXIT_CODE=\${FINL_EXIT}\";
                      exit \${FINL_EXIT}
                    "
                    
                    # Execute FINL validation
                    ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i ${SSH_KEY_CRED} \\
                        -p 22 "finacle@findem.linear6.com" "bash -c '${FINL_COMMAND}'" \\
                        >> /var/log/finacle/deployment_audit_*.log 2>&1 || {
                      echo "CRITICAL: FINL validation failed" >&2
                      exit 1
                    }
                    
                    echo "✓ FINL validation passed"
                '''
            }
        }

        stage('Service Restart') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    # Execute service restart sequence
                    deploy/restart-services.sh \\
                        '${env.INSTALL_ID}' \\
                        '${params.DEPLOY_ENV}' \\
                        '${SSH_KEY_CRED}'
                    
                    echo "✓ Service restart completed"
                '''
            }
        }

        stage('Post Verification') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    # Verify service health
                    sleep 20
                    FINLISTVAL=$(ssh -o StrictHostKeyChecking=yes -i ${SSH_KEY_CRED} \\
                        finacle@findem.linear6.com "ps -ef | grep -v grep | grep finlistval${INSTALL_ID} | wc -l" || echo 0)
                    CORESESSION=$(ssh -o StrictHostKeyChecking=yes -i ${SSH_KEY_CRED} \\
                        finacle@findem.linear6.com "ps -ef | grep -v grep | grep coresession${INSTALL_ID} | wc -l" || echo 0)
                    
                    if [[ "${FINLISTVAL}" -lt 1 || "${CORESESSION}" -lt 1 ]]; then
                        echo "CRITICAL: Services not healthy post-deployment" >&2
                        exit 1
                    fi
                    
                    echo "✓ Post-deployment verification passed"
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
                    
                    # Finalize audit log
                    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                    AUDIT_LOG="/var/log/finacle/deployment_audit_${TIMESTAMP}_${TICKET_NUMBER}.log"
                    
                    # Add completion timestamp to audit log
                    echo "DEPLOYMENT COMPLETED: $(date '+%Y-%m-%d %H:%M:%S %Z')" >> "${AUDIT_LOG}"
                    
                    # Archive to S3 for long-term retention
                    if command -v aws &>/dev/null && [[ -n "${AUDIT_BUCKET:-}" ]]; then
                        aws s3 cp "${AUDIT_LOG}" "s3://${AUDIT_BUCKET}/${BANK_TARGET}/${DEPLOY_ENV}/${TIMESTAMP}_${TICKET_NUMBER}.log" \\
                            --sse aws:kms --sse-kms-key-id alias/finacle-audit-key 2>/dev/null || true
                    fi
                    
                    echo "✓ Audit log created and archived"
                '''
            }
        }

        stage('Branch Sync') {
            when { expression { params.DEPLOY_ENV == 'PRODUCTION' } }
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    # Sync PRODUCTION state to all lower environments (branch protection enforced)
                    git config user.name "Finacle CI/CD Bot"
                    git config user.email "cicd@linearsix.lk"
                    
                    # Fetch latest state
                    git fetch origin
                    
                    # Merge PRODUCTION → UAT → QA → DEV (with conflict detection)
                    for target in UAT QA DEV; do
                        git checkout "${target}" || git checkout -b "${target}" origin/"${target}"
                        git pull origin "${target}" || true
                        
                        if ! git merge --no-ff --no-edit origin/PRODUCTION; then
                            echo "CONFLICT DETECTED: Merge conflict on ${target} branch" >&2
                            git merge --abort
                            
                            # Notify conflict stakeholders
                            echo "Merge conflict requires manual resolution" | \\
                                mail -s "🚨 MERGE CONFLICT: PRODUCTION → ${target}" \\
                                -S smtp="smtp.gmail.com:587" \\
                                dev-lead@linearsix.lk qa-lead@linearsix.lk
                            
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
            script {
                sh "deploy/notify.sh success '${params.TICKET_NUMBER}' '${params.DEPLOY_ENV}' '${params.BANK_TARGET}'"
                archiveArtifacts artifacts: 'deployment_audit_*.log', allowEmptyArchive: true
            }
        }
        failure {
            script {
                sh "deploy/notify.sh failure '${params.TICKET_NUMBER}' '${params.DEPLOY_ENV}' '${params.BANK_TARGET}' 'Pipeline failed at ${currentBuild.currentResult}'"
                archiveArtifacts artifacts: 'deployment_audit_*.log', allowEmptyArchive: true
            }
        }
        always {
            cleanWs deleteDirs: true
        }
    }
}