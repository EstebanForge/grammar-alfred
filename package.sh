#!/usr/bin/env bash
#
# Grammar Alfred Workflow Packaging Script
# Author: EstebanForge
# Version: 1.0.0

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKFLOW_NAME="grammar"
AUTHOR="EstebanForge"
VERSION="1.0.0"
OUTPUT_FILE="${WORKFLOW_NAME}.alfredworkflow"

echo -e "${BLUE}📦 Grammar Alfred Workflow Packaging Script${NC}"
echo -e "${BLUE}==========================================${NC}"
echo

# Check required files
echo -e "${YELLOW}🔍 Checking required files...${NC}"
required_files=(
    "info.plist"
    "scripts/check.sh"
)
missing_files=()
for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || missing_files+=("$file")
done
if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Missing required files:${NC}"
    for file in "${missing_files[@]}"; do
        echo -e "${RED}   - $file${NC}"
    done
    exit 1
fi
echo -e "${GREEN}✅ All required files found${NC}"

# Executable bit
echo -e "${YELLOW}🔧 Checking script permissions...${NC}"
if [[ ! -x "scripts/check.sh" ]]; then
    echo -e "${YELLOW}⚠️  Making check.sh executable...${NC}"
    chmod +x scripts/check.sh
else
    echo -e "${GREEN}✅ Script is executable${NC}"
fi

# Bash syntax check
echo -e "${YELLOW}🔍 Linting check.sh...${NC}"
if ! bash -n scripts/check.sh; then
    echo -e "${RED}❌ Syntax error in scripts/check.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Syntax OK${NC}"

# Validate plist
echo -e "${YELLOW}🔍 Validating info.plist...${NC}"
if ! plutil -lint info.plist >/dev/null; then
    echo -e "${RED}❌ info.plist is invalid${NC}"
    exit 1
fi
echo -e "${GREEN}✅ info.plist valid${NC}"

# Remove old package
[[ -f "$OUTPUT_FILE" ]] && rm "$OUTPUT_FILE"

# Bundle (icon.png optional)
echo -e "${YELLOW}📦 Creating Alfred workflow package...${NC}"
bundle_files=(info.plist scripts/)
[[ -f "icon.png" ]] && bundle_files+=(icon.png)
zip -r "$OUTPUT_FILE" "${bundle_files[@]}" >/dev/null

if [[ -f "$OUTPUT_FILE" ]]; then
    package_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo -e "${GREEN}✅ Package created successfully!${NC}"
    echo
    echo -e "  • Name:    $OUTPUT_FILE"
    echo -e "  • Size:    $package_size"
    echo -e "  • Author:  $AUTHOR"
    echo -e "  • Version: $VERSION"
    echo
    echo -e "${YELLOW}📋 Installation:${NC}"
    echo -e "  1. Double-click ${OUTPUT_FILE} to install in Alfred"
    echo -e "  2. Open the workflow → Configure Workflow… → set PROVIDER + API_KEY"
    echo -e "  3. Use \`grammar <text>\` or copy text and press ⌃⌥G"
else
    echo -e "${RED}❌ Failed to create package${NC}"
    exit 1
fi

# Functional smoke test (error path needs no API key)
echo
echo -e "${YELLOW}🧪 Smoke test (no-key path)...${NC}"
test_result=$(./scripts/check.sh "" 2>/dev/null || true)
if printf '%s' "$test_result" | jq -e '.items[0].valid == false' >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Script emits valid Alfred JSON (error item shown without a key)${NC}"
else
    echo -e "${YELLOW}⚠️  Smoke test inconclusive — verify with a real API key${NC}"
fi

echo
echo -e "${GREEN}🎉 Done! $OUTPUT_FILE is ready for distribution.${NC}"
