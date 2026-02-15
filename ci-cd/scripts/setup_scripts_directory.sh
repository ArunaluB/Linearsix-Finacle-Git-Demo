#!/bin/bash
#################################################################
# Setup Script for Finacle CI/CD Pipeline
# This script sets up the scripts directory in your repository
# Run this from your repository root directory
#################################################################

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║    Finacle CI/CD Pipeline - Scripts Directory Setup          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Error: Not in a git repository root"
    echo "Please run this script from your repository root directory"
    exit 1
fi

echo "✅ Git repository detected"
echo ""

# Create scripts directory
echo "📁 Creating scripts directory..."
mkdir -p scripts
echo "✅ Created: ./scripts/"
echo ""

# Check if user has the script files
echo "📋 Required scripts:"
echo "   - backup_files.sh"
echo "   - cleanup_dev_versions_qa.sh"
echo "   - cleanup_previous_deployment.sh"
echo "   - create_patch_structure.sh"
echo "   - deploy_com_mrt.sh"
echo "   - deploy_scr.sh"
echo "   - deploy_sql.sh"
echo "   - generate_audit_log.sh"
echo "   - merge_feature_branches_dev.sh"
echo "   - restart_services.sh"
echo "   - rollback_deployment.sh"
echo "   - run_finl.sh"
echo "   - sync_branches_from_production.sh"
echo "   - validate_file_headers.sh"
echo "   - verify_deployment.sh"
echo ""

# Instructions
echo "ℹ️  Next Steps:"
echo ""
echo "1. Copy your deployment scripts to the scripts/ directory:"
echo "   cp /path/to/your/scripts/*.sh scripts/"
echo ""
echo "2. Make scripts executable:"
echo "   chmod +x scripts/*.sh"
echo ""
echo "3. Add scripts to git:"
echo "   git add scripts/"
echo "   git commit -m \"Add deployment scripts\""
echo "   git push origin dev"
echo ""
echo "4. (Optional) Configure email credential in Jenkins:"
echo "   - Go to Jenkins → Manage Jenkins → Credentials"
echo "   - Add credential:"
echo "     * Type: Secret text"
echo "     * ID: finacle-deployment-email"
echo "     * Secret: your-email@company.com"
echo ""
echo "5. Run your Jenkins pipeline!"
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║    Setup Complete! Add your scripts and commit to git         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
