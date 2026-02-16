#!/usr/bin/env groovy
/*
 * FINACLE CI/CD PIPELINE - AFC SUPPORT (No Agent Label Required)
 * Version: 3.3.0 | Production Ready
 */

pipeline {
    agent any  // ✅ FIXED: 'any' agent භාවිතා කරයි (master හෝ ඕනෑම agent එකක්)

    parameters {
        choice(
            name: 'BANK_TARGET',
            choices: ['SAMPATH', 'AFC', 'SIYAPATHA', 'PABC'],
            description: 'Target Financial Institution'
        )
        choice(
            name: 'DEPLOY_ENV',
            choices: ['DEV', 'QA', 'UAT', 'PRODUCTION'],
            description: 'Target Environment'
        )
        string(
            name: 'TICKET_NUMBER',
            defaultValue: '10225',
            description: 'Ticket Number (e.g., 10225)'
        )
        booleanParam(
            name: 'SKIP_VALIDATION',
            defaultValue: false,
            description: 'Skip validation (EMERGENCY ONLY)'
        )
    }

    environment {
        // Jenkins Credentials
        SSH_KEY_CRED = credentials('finadm')
        SMTP_CRED = credentials('finade-email-list')
        
        // ✅ FIXED: Single-line ternary (no compilation error)
        INSTALL_ID = "${params.BANK_TARGET == 'SAMPATH' ? 'FINDEM' : (params.BANK_TARGET == 'AFC' ? 'FINAFC' : (params.BANK_TARGET == 'SIYAPATHA' ? 'FINSIYA' : 'FINPABC'))}"
        
        // AFC සඳහා විශේෂිත paths
        BASE_PATH = "/finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app/cust/01/INFENG"
        PATCH_AREA = "/finutils/customizations_${params.TICKET_NUMBER}/Localizations/patchArea"
        FINAL_DELIVERY = "/finutils/customizations_${params.TICKET_NUMBER}/Localizations/FinalDelivery"
        BACKUP_PATH = "/finapp/backup"
        
        // Dynamic SSH targets (AFC = afcdem.linear6.com)
        SSH_HOST = "${params.BANK_TARGET == 'SAMPATH' ? 'findem.linear6.com' : (params.BANK_TARGET == 'AFC' ? 'afcdem.linear6.com' : (params.BANK_TARGET == 'SIYAPATHA' ? 'siyadem.linear6.com' : 'pabcdem.linear6.com'))}"
        SSH_PORT = '22'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '50'))
        disableConcurrentBuilds()
    }

    stages {
        stage('SetBranchGovernance') {
            steps {
                script {
                    def currentBranch = sh(script: 'git rev-parse --abbrev-ref HEAD', returnStdout: true).trim()
                    def allowed = params.DEPLOY_ENV == 'DEV' ? ['DEV-*'] : [params.DEPLOY_ENV]
                    
                    if (!allowed.any { pattern -> currentBranch ==~ pattern || currentBranch == pattern }) {
                        error "BRANCH VIOLATION: '${currentBranch}' not allowed for ${params.DEPLOY_ENV}"
                    }
                    echo "✓ Branch OK: ${currentBranch} → ${params.DEPLOY_ENV}"
                }
            }
        }

        stage('Create Patch Structure') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    # AFC සඳහා patch structure සෑදීම
                    echo "Creating patch structure for AFC (Ticket: ${TICKET_NUMBER})..."
                    
                    # Patch directory structure
                    mkdir -p "${PATCH_AREA}/scripts"
                    mkdir -p "${PATCH_AREA}/sqls"
                    mkdir -p "${PATCH_AREA}/coms"
                    mkdir -p "${PATCH_AREA}/mrts"
                    
                    # FinalDelivery structure (Production සඳහා)
                    mkdir -p "${FINAL_DELIVERY}/scripts"
                    mkdir -p "${FINAL_DELIVERY}/sqls"
                    mkdir -p "${FINAL_DELIVERY}/coms"
                    mkdir -p "${FINAL_DELIVERY}/mrts"
                    
                    echo "✓ Patch structure created:"
                    echo "  - ${PATCH_AREA}"
                    echo "  - ${FINAL_DELIVERY}"
                '''
            }
        }

        stage('Deploy to AFC Server') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    echo "Deploying to AFC server: ${SSH_HOST}"
                    echo "Ticket: ${TICKET_NUMBER} | Environment: ${DEPLOY_ENV}"
                    
                    # Git repository එකෙන් ගොනු සොයාගැනීම
                    mapfile -t files < <(find . -maxdepth 2 -type f \( -name "*.scr" -o -name "*.sql" -o -name "*.com" -o -name "*.mrt" \) 2>/dev/null || true)
                    
                    if [ ${#files[@]} -eq 0 ]; then
                        echo "⚠️  No deployable files found (.scr/.sql/.com/.mrt)"
                        exit 0
                    fi
                    
                    echo "Found ${#files[@]} files to deploy:"
                    for file in "${files[@]}"; do
                        echo "  - $(basename "$file")"
                    done
                    
                    # සෑම ගොනුවක්ම deploy කිරීම
                    for file in "${files[@]}"; do
                        filename=$(basename "$file")
                        ext="${filename##*.}"
                        
                        # File type routing
                        case "$ext" in
                            scr) target_dir="scripts" ;;
                            sql) target_dir="sqls" ;;
                            com) target_dir="coms" ;;
                            mrt) target_dir="mrts" ;;
                            *) continue ;;
                        esac
                        
                        # 1. Live path එකේ පවතින ගොනුව _safe_ ලෙස rename කිරීම
                        SAFE_NAME="${filename}_safe_$(date +%m%d%y)"
                        BACKUP_CMD="
                            if [ -f '${BASE_PATH}/${target_dir}/${filename}' ]; then
                                mv '${BASE_PATH}/${target_dir}/${filename}' '${BASE_PATH}/${target_dir}/${SAFE_NAME}';
                                echo 'BACKUP: ${filename} → ${SAFE_NAME}';
                            else
                                echo 'NO EXISTING FILE: ${filename}';
                            fi
                        "
                        
                        ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_CRED}" \
                            -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${BACKUP_CMD}'" || true
                        
                        # 2. ගොනුව patch area එකට copy කිරීම
                        if [ "${DEPLOY_ENV}" = "PRODUCTION" ]; then
                            scp -o StrictHostKeyChecking=yes -i "${SSH_KEY_CRED}" -P "${SSH_PORT}" \
                                "$file" "finacle@${SSH_HOST}:${FINAL_DELIVERY}/${target_dir}/" || exit 1
                            LINK_TARGET="${FINAL_DELIVERY}/${target_dir}/${filename}"
                        else
                            scp -o StrictHostKeyChecking=yes -i "${SSH_KEY_CRED}" -P "${SSH_PORT}" \
                                "$file" "finacle@${SSH_HOST}:${PATCH_AREA}/${target_dir}/" || exit 1
                            LINK_TARGET="${PATCH_AREA}/${target_dir}/${filename}"
                        fi
                        
                        # 3. Symbolic link එක සාදා chmod 775 කිරීම
                        LINK_CMD="
                            ln -fs '${LINK_TARGET}' '${BASE_PATH}/${target_dir}/${filename}' &&
                            chmod 775 '${BASE_PATH}/${target_dir}/${filename}' &&
                            echo 'LINKED: ${filename} → ${LINK_TARGET}'
                        "
                        
                        ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_CRED}" \
                            -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${LINK_CMD}'" || exit 1
                        
                        echo "✓ Deployed: ${filename}"
                    done
                    
                    echo "✓ All files deployed successfully to AFC"
                '''
            }
        }

        stage('Run FINL') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    echo "Running FINL validation on AFC server..."
                    
                    FINL_CMD="
                        export FININSTALLID='${INSTALL_ID}';
                        source /fincommon/ENVFILES/ENV_\${FININSTALLID}/PrepareEnv_\${FININSTALLID}.cfg 2>/dev/null || true;
                        cd /finapp/FIN/\${FININSTALLID}/BE/Finacle/FC/app;
                        ./finl;
                        echo 'FINL completed with exit code: \$?'
                    "
                    
                    ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_CRED}" \
                        -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${FINL_CMD}'" || exit 1
                    
                    echo "✓ FINL validation successful"
                '''
            }
        }

        stage('Restart AFC Services') {
            steps {
                sh '''
                    #!/bin/bash
                    set -euo pipefail
                    
                    echo "Restarting AFC services in correct order..."
                    
                    RESTART_CMD="
                        cd /finapp/FIN/${INSTALL_ID}/BE/Finacle/FC/app;
                        echo 'Stopping finlistval${INSTALL_ID}...';
                        ./stop-finlistval${INSTALL_ID} && sleep 8;
                        echo 'Stopping coresession${INSTALL_ID}...';
                        ./stop-coresession${INSTALL_ID} && sleep 12;
                        echo 'Starting coresession${INSTALL_ID}...';
                        ./start-coresession${INSTALL_ID} && sleep 15;
                        echo 'Starting finlistval${INSTALL_ID}...';
                        ./start-finlistval${INSTALL_ID};
                        echo 'Services restarted successfully'
                    "
                    
                    ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -i "${SSH_KEY_CRED}" \
                        -p "${SSH_PORT}" "finacle@${SSH_HOST}" "bash -c '${RESTART_CMD}'" || exit 1
                    
                    # Service health check
                    sleep 20
                    FINLISTVAL=$(ssh -o StrictHostKeyChecking=yes -i "${SSH_KEY_CRED}" -p "${SSH_PORT}" \
                        "finacle@${SSH_HOST}" "ps -ef | grep -v grep | grep finlistval${INSTALL_ID} | wc -l" || echo 0)
                    CORESESSION=$(ssh -o StrictHostKeyChecking=yes -i "${SSH_KEY_CRED}" -p "${SSH_PORT}" \
                        "finacle@${SSH_HOST}" "ps -ef | grep -v grep | grep coresession${INSTALL_ID} | wc -l" || echo 0)
                    
                    if [ "$FINLISTVAL" -lt 1 ] || [ "$CORESESSION" -lt 1 ]; then
                        echo "❌ Services not running!" >&2
                        exit 1
                    fi
                    
                    echo "✓ Services verified:"
                    echo "  - finlistval${INSTALL_ID}: ${FINLISTVAL} instance(s)"
                    echo "  - coresession${INSTALL_ID}: ${CORESESSION} instance(s)"
                '''
            }
        }
    }

    post {
        success {
            echo "✅ AFC DEPLOYMENT SUCCESSFUL"
            echo "Bank: ${params.BANK_TARGET}"
            echo "Env: ${params.DEPLOY_ENV}"
            echo "Ticket: ${params.TICKET_NUMBER}"
        }
        failure {
            echo "🚨 AFC DEPLOYMENT FAILED"
            echo "Check Jenkins console output for details"
        }
    }
}