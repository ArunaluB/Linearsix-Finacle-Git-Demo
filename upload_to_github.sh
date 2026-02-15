#!/bin/bash
#################################################################
# Name: upload_to_github.sh
# Description: Automated script to upload Finacle CI/CD system to GitHub
# Date: 2026-02-15
# Author: DevOps Team
# Input: GitHub repository URL
# Output: Files uploaded to GitHub
# Tables Used: None
# Calling Script: Manual execution
#################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}"
cat << "BANNER"
╔═══════════════════════════════════════════════════════════╗
║   Finacle CI/CD System - GitHub Upload Script            ║
║   Automated Upload to Repository                         ║
╚═══════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# Configuration
REPO_URL="https://github.com/ArunaluB/Linearsix-Finacle-Git-Demo.git"
WORK_DIR="/tmp/finacle-upload-$$"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BLUE}Source directory: ${SOURCE_DIR}${NC}"
echo ""

# Step 1: Prerequisites check
echo -e "${YELLOW}[1/8] Checking prerequisites...${NC}"

if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: Git is not installed${NC}"
    echo "Please install Git first: https://git-scm.com/downloads"
    exit 1
fi

echo -e "${GREEN}✓ Git installed: $(git --version)${NC}"

# Check if already in a git repo
if [ -d ".git" ]; then
    echo -e "${GREEN}✓ Already in a git repository${NC}"
    ALREADY_IN_REPO=true
else
    ALREADY_IN_REPO=false
fi

# Step 2: Get repository URL
echo -e "${YELLOW}[2/8] Repository configuration...${NC}"

if [ "$ALREADY_IN_REPO" = false ]; then
    read -p "Enter GitHub repository URL (default: ${REPO_URL}): " USER_REPO
    REPO_URL=${USER_REPO:-$REPO_URL}
    echo -e "${GREEN}✓ Repository: ${REPO_URL}${NC}"
fi

# Step 3: Clone or use existing repo
echo -e "${YELLOW}[3/8] Preparing repository...${NC}"

if [ "$ALREADY_IN_REPO" = false ]; then
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    echo "Cloning repository..."
    if git clone "$REPO_URL" repo; then
        cd repo
        echo -e "${GREEN}✓ Repository cloned${NC}"
    else
        echo -e "${RED}Error: Failed to clone repository${NC}"
        echo "Please check:"
        echo "1. Repository URL is correct"
        echo "2. You have access to the repository"
        echo "3. Git credentials are configured"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Using current repository${NC}"
fi

# Step 4: Check/Create DEV branch
echo -e "${YELLOW}[4/8] Setting up DEV branch...${NC}"

if git rev-parse --verify DEV >/dev/null 2>&1; then
    git checkout DEV
    echo -e "${GREEN}✓ Switched to DEV branch${NC}"
else
    git checkout -b DEV
    echo -e "${GREEN}✓ Created DEV branch${NC}"
fi

# Step 5: Copy files
echo -e "${YELLOW}[5/8] Copying files...${NC}"

# Create directory structure
mkdir -p scripts
mkdir -p docs

# Copy Jenkinsfile and main script
if [ "$ALREADY_IN_REPO" = false ]; then
    cp "${SOURCE_DIR}/Jenkinsfile" .
    cp "${SOURCE_DIR}/local_pc_deploy.sh" .
fi

# Copy scripts
if [ "$ALREADY_IN_REPO" = false ]; then
    cp "${SOURCE_DIR}"/scripts/*.sh scripts/
fi

# Copy documentation
if [ "$ALREADY_IN_REPO" = false ]; then
    cp "${SOURCE_DIR}"/README.md .
    cp "${SOURCE_DIR}"/*.md docs/ 2>/dev/null || true
    mv docs/README.md . 2>/dev/null || true
fi

echo -e "${GREEN}✓ Files copied${NC}"

# Step 6: Make scripts executable
echo -e "${YELLOW}[6/8] Setting permissions...${NC}"

chmod +x scripts/*.sh 2>/dev/null || true
chmod +x local_pc_deploy.sh 2>/dev/null || true

echo -e "${GREEN}✓ Permissions set${NC}"

# Step 7: Create .gitignore if not exists
echo -e "${YELLOW}[7/8] Creating .gitignore...${NC}"

if [ ! -f .gitignore ]; then
    cat > .gitignore << 'GITIGNORE'
# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
desktop.ini

# Logs
*.log
logs/

# Temporary files
*.tmp
.temp/
tmp/

# Sensitive data
*.key
*.pem
config/secrets.yml
credentials.yml

# Build artifacts
*.class
*.jar
*.war
target/
build/

# Node modules (if any)
node_modules/

# Python
__pycache__/
*.pyc
*.pyo
.venv/

# Backup files
*~
*.bak
*.backup
GITIGNORE
    echo -e "${GREEN}✓ .gitignore created${NC}"
else
    echo -e "${GREEN}✓ .gitignore already exists${NC}"
fi

# Step 8: Git add, commit, push
echo -e "${YELLOW}[8/8] Committing and pushing to GitHub...${NC}"

# Add all files
git add .

# Check if there are changes
if git diff --staged --quiet; then
    echo -e "${YELLOW}No changes to commit${NC}"
else
    # Show what will be committed
    echo "Files to be committed:"
    git status --short
    echo ""
    
    # Commit
    git commit -m "feat: Add complete Finacle CI/CD automation system

Added components:
- Jenkinsfile for multi-environment CI/CD (DEV/QA/UAT/PRODUCTION)
- 15 deployment automation scripts
- Complete documentation (10 files)
- Backup and rollback mechanisms
- GitHub and Jenkins setup guides
- Local PC deployment option

Features:
- Automatic deployment on push
- Developer-specific file naming in DEV
- Canonical file deployment in QA/UAT
- Smart backup strategy
- Branch protection and approval gates
- Complete audit logging
- Email notifications
- Rollback support

Documentation:
- README.md - Main documentation
- QUICKSTART.md - 5-minute setup
- JENKINS_SETUP.md - Jenkins configuration
- GITHUB_SETUP.md - GitHub setup guide
- BACKUP_STRATEGY.md - Backup strategy
- REAL_EXAMPLE.md - Real-world examples
- FOLDER_STRUCTURE.md - Structure details
- HOW_TO_UPLOAD.md - Upload instructions
- CONFIG_TEMPLATE.md - Configuration templates
- PROJECT_SUMMARY.md - Executive summary"

    echo -e "${GREEN}✓ Changes committed${NC}"
    
    # Push to GitHub
    echo "Pushing to GitHub..."
    if git push origin DEV; then
        echo -e "${GREEN}✓ Successfully pushed to GitHub!${NC}"
    else
        echo -e "${RED}Error: Failed to push to GitHub${NC}"
        echo ""
        echo "This might be due to:"
        echo "1. Authentication required - set up SSH key or Personal Access Token"
        echo "2. No write access to repository"
        echo "3. Branch protection rules"
        echo ""
        echo "To push manually:"
        echo "  cd $(pwd)"
        echo "  git push origin DEV"
        exit 1
    fi
fi

# Cleanup
if [ "$ALREADY_IN_REPO" = false ]; then
    cd /
    rm -rf "$WORK_DIR"
fi

# Success message
echo ""
echo -e "${GREEN}"
cat << "SUCCESS"
╔═══════════════════════════════════════════════════════════╗
║                  SUCCESS! ✓                               ║
║   Files uploaded to GitHub successfully                   ║
╚═══════════════════════════════════════════════════════════╝
SUCCESS
echo -e "${NC}"

echo -e "${BLUE}Repository: ${REPO_URL}${NC}"
echo -e "${BLUE}Branch: DEV${NC}"
echo ""
echo "Next steps:"
echo "1. Visit: ${REPO_URL}"
echo "2. Verify all files are present"
echo "3. Set up branch protection rules (see GITHUB_SETUP.md)"
echo "4. Configure Jenkins (see JENKINS_SETUP.md)"
echo "5. Follow QUICKSTART.md for deployment"
echo ""
echo -e "${GREEN}Happy deploying! 🚀${NC}"
