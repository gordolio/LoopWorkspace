#!/bin/bash
#
# sync_all.sh
#
# One-command sync script for the AI Carb Entry feature branch.
# Keeps LoopWorkspace and the Loop submodule in sync with upstream.
#
# Usage: Scripts/sync_all.sh
#
# What this script does:
# 1. Fetches latest from upstream LoopWorkspace
# 2. Merges upstream into your ai-carb-entry branch
# 3. Updates all submodules to match
# 4. Merges upstream Loop changes into your Loop feature branch
# 5. Commits everything and pushes
#
# If conflicts occur, the script stops and gives clear instructions.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE_BRANCH="ai-carb-entry"
LOOP_BRANCH="ai-carb-entry"
FORK_REMOTE="gordolio"

# Get the workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$WORKSPACE_ROOT"

echo -e "${BLUE}${BOLD}=== Loop AI Carb Entry Sync ===${NC}"
echo ""

# Function to check for uncommitted changes
check_clean() {
    local dir="$1"
    local name="$2"
    cd "$dir"
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo -e "${RED}Error: $name has uncommitted changes.${NC}"
        echo "Please commit or stash your changes first:"
        echo "  cd $dir"
        echo "  git status"
        exit 1
    fi
    cd "$WORKSPACE_ROOT"
}

# Function to handle merge conflicts
handle_conflict() {
    local location="$1"
    echo ""
    echo -e "${RED}${BOLD}=== MERGE CONFLICT ===${NC}"
    echo ""
    echo -e "A merge conflict occurred in ${YELLOW}$location${NC}."
    echo ""
    echo -e "${BOLD}What to do:${NC}"
    echo "1. Open the project in Xcode or your preferred merge tool"
    echo "2. Resolve the conflicts in the listed files"
    echo "3. Run: git add <resolved-files>"
    echo "4. Run: git commit"
    echo "5. Re-run this script: Scripts/sync_all.sh"
    echo ""
    echo "Or to abort and go back to before the merge:"
    echo "  git merge --abort"
    echo ""
    exit 1
}

# Step 0: Verify we're on the right branches and clean
echo -e "${YELLOW}Checking current state...${NC}"

# Check LoopWorkspace
CURRENT_WS_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_WS_BRANCH" != "$WORKSPACE_BRANCH" ]; then
    echo -e "${YELLOW}Switching LoopWorkspace to $WORKSPACE_BRANCH...${NC}"
    git checkout "$WORKSPACE_BRANCH" 2>/dev/null || {
        echo -e "${RED}Branch $WORKSPACE_BRANCH doesn't exist in LoopWorkspace.${NC}"
        echo "Create it first with: git checkout -b $WORKSPACE_BRANCH"
        exit 1
    }
fi

check_clean "$WORKSPACE_ROOT" "LoopWorkspace"

# Check Loop submodule
cd Loop
CURRENT_LOOP_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_LOOP_BRANCH" != "$LOOP_BRANCH" ]; then
    echo -e "${YELLOW}Switching Loop to $LOOP_BRANCH...${NC}"
    git checkout "$LOOP_BRANCH" 2>/dev/null || {
        echo -e "${RED}Branch $LOOP_BRANCH doesn't exist in Loop.${NC}"
        exit 1
    }
fi
check_clean "$WORKSPACE_ROOT/Loop" "Loop submodule"
cd "$WORKSPACE_ROOT"

echo -e "${GREEN}✓ On correct branches and working tree is clean${NC}"
echo ""

# Step 1: Fetch everything
echo -e "${YELLOW}Step 1: Fetching from upstream...${NC}"
git fetch origin main
cd Loop && git fetch origin && cd "$WORKSPACE_ROOT"
echo -e "${GREEN}✓ Fetched latest from upstream${NC}"
echo ""

# Step 2: Check if LoopWorkspace needs updating
echo -e "${YELLOW}Step 2: Checking LoopWorkspace...${NC}"
WS_BEHIND=$(git rev-list HEAD..origin/main --count)
if [ "$WS_BEHIND" -eq 0 ]; then
    echo -e "${GREEN}✓ LoopWorkspace is up to date${NC}"
else
    echo "LoopWorkspace is $WS_BEHIND commits behind upstream."
    echo -e "Merging origin/main into $WORKSPACE_BRANCH..."

    if ! git merge origin/main -m "Merge upstream LoopWorkspace into $WORKSPACE_BRANCH"; then
        handle_conflict "LoopWorkspace"
    fi
    echo -e "${GREEN}✓ Merged upstream LoopWorkspace${NC}"
fi
echo ""

# Step 3: Update all OTHER submodules (not Loop)
echo -e "${YELLOW}Step 3: Updating other submodules...${NC}"
# Get list of submodules except Loop
SUBMODULES=$(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | grep -v '^Loop$')
for sub in $SUBMODULES; do
    if [ -d "$sub" ]; then
        echo "  Updating $sub..."
        git submodule update --init "$sub" 2>/dev/null || true
    fi
done
echo -e "${GREEN}✓ Other submodules updated${NC}"
echo ""

# Step 4: Sync Loop feature branch with upstream
echo -e "${YELLOW}Step 4: Syncing Loop feature branch...${NC}"

# Get the commit that LoopWorkspace expects for Loop
UPSTREAM_LOOP_COMMIT=$(git ls-tree HEAD Loop | awk '{print $3}')
echo "LoopWorkspace expects Loop at: $UPSTREAM_LOOP_COMMIT"

cd Loop

# Check if we already have this commit in our history
if git merge-base --is-ancestor "$UPSTREAM_LOOP_COMMIT" HEAD; then
    echo -e "${GREEN}✓ Loop feature branch already includes upstream changes${NC}"
else
    echo "Merging upstream Loop changes into $LOOP_BRANCH..."
    UPSTREAM_DESC=$(git log --oneline -1 "$UPSTREAM_LOOP_COMMIT")

    if ! git merge "$UPSTREAM_LOOP_COMMIT" -m "Merge upstream LoopKit/Loop into $LOOP_BRANCH

Syncing with LoopWorkspace which tracks:
$UPSTREAM_DESC"; then
        handle_conflict "Loop submodule"
    fi
    echo -e "${GREEN}✓ Merged upstream Loop changes${NC}"
fi

cd "$WORKSPACE_ROOT"
echo ""

# Step 5: Commit the Loop submodule pointer if changed
echo -e "${YELLOW}Step 5: Updating LoopWorkspace to point to Loop feature branch...${NC}"
if git diff --quiet Loop; then
    echo -e "${GREEN}✓ Loop pointer already up to date${NC}"
else
    git add Loop
    git commit -m "Update Loop to latest $LOOP_BRANCH"
    echo -e "${GREEN}✓ Committed Loop pointer update${NC}"
fi
echo ""

# Step 6: Push everything
echo -e "${YELLOW}Step 6: Pushing changes...${NC}"

# Check if fork remote exists
if ! git remote get-url "$FORK_REMOTE" > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Remote '$FORK_REMOTE' not found in LoopWorkspace.${NC}"
    echo "Add it with: git remote add $FORK_REMOTE git@github.com:$FORK_REMOTE/LoopWorkspace.git"
    echo ""
    echo "Skipping push for LoopWorkspace."
else
    echo "Pushing LoopWorkspace..."
    git push "$FORK_REMOTE" "$WORKSPACE_BRANCH" || {
        echo -e "${YELLOW}Warning: Could not push LoopWorkspace. You may need to push manually.${NC}"
    }
fi

cd Loop
if git remote get-url "$FORK_REMOTE" > /dev/null 2>&1; then
    echo "Pushing Loop..."
    git push "$FORK_REMOTE" "$LOOP_BRANCH" || {
        echo -e "${YELLOW}Warning: Could not push Loop. You may need to push manually.${NC}"
    }
else
    echo -e "${YELLOW}Warning: Remote '$FORK_REMOTE' not found in Loop.${NC}"
fi
cd "$WORKSPACE_ROOT"

echo ""
echo -e "${GREEN}${BOLD}=== Sync Complete! ===${NC}"
echo ""
echo "Current state:"
echo "  LoopWorkspace: $(git log --oneline -1)"
echo "  Loop:          $(cd Loop && git log --oneline -1)"
echo ""
echo "You can now build and test the project."
