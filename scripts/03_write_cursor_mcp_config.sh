#!/bin/bash
#
# 03_write_cursor_mcp_config.sh - Generate Cursor MCP configuration
#
# This script:
# 1. Verifies SSH connection works
# 2. Creates .cursor/mcp.json with SSH MCP server config
# 3. Prints next steps
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SSH_HOST="blade18-tb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CURSOR_DIR="$PROJECT_DIR/.cursor"
MCP_CONFIG="$CURSOR_DIR/mcp.json"

echo "========================================"
echo "ThunderMirror - Cursor MCP Setup"
echo "========================================"
echo ""

# Step 1: Verify SSH works
echo "[1/3] Verifying SSH connection..."

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" "whoami" > /dev/null 2>&1; then
    echo -e "      ${RED}FAIL: Cannot connect to $SSH_HOST${NC}"
    echo ""
    echo "      SSH must work before configuring MCP."
    echo "      Run: ./scripts/02_verify_ssh_mac.sh"
    echo ""
    exit 1
fi

echo -e "      ${GREEN}OK: SSH connection works${NC}"

# Step 2: Check for Node.js/npx
echo ""
echo "[2/3] Checking Node.js..."

if ! command -v npx &> /dev/null; then
    echo -e "      ${YELLOW}WARNING: npx not found${NC}"
    echo ""
    echo "      MCP requires Node.js. Install with:"
    echo "      brew install node"
    echo ""
    echo "      Continuing anyway (you can install Node.js later)..."
else
    NPX_VERSION=$(npx --version 2>/dev/null)
    echo -e "      ${GREEN}OK: npx version $NPX_VERSION${NC}"
fi

# Step 3: Write MCP config
echo ""
echo "[3/3] Writing MCP configuration..."

mkdir -p "$CURSOR_DIR"

# Write the MCP config
cat > "$MCP_CONFIG" << 'EOF'
{
  "mcpServers": {
    "blade18-tb": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic/mcp-ssh@latest",
        "--host",
        "blade18-tb"
      ],
      "env": {}
    }
  }
}
EOF

echo -e "      ${GREEN}OK: Created $MCP_CONFIG${NC}"

# Verify JSON is valid
if command -v python3 &> /dev/null; then
    if python3 -m json.tool "$MCP_CONFIG" > /dev/null 2>&1; then
        echo -e "      ${GREEN}OK: JSON syntax valid${NC}"
    else
        echo -e "      ${YELLOW}WARNING: JSON may be invalid${NC}"
    fi
fi

# Summary
echo ""
echo "========================================"
echo -e "${GREEN}✅ MCP configuration complete!${NC}"
echo "========================================"
echo ""
echo "Configuration written to: $MCP_CONFIG"
echo ""
cat "$MCP_CONFIG"
echo ""
echo "========================================"
echo "Next steps:"
echo "========================================"
echo ""
echo "1. Restart Cursor IDE completely (Cmd+Q, then reopen)"
echo ""
echo "2. Verify MCP server is connected:"
echo "   - Open Cursor Settings (Cmd+,)"
echo "   - Go to: Features → MCP Servers"
echo "   - 'blade18-tb' should appear and show 'Connected'"
echo ""
echo "3. If MCP doesn't appear:"
echo "   - Check that Node.js is installed: node --version"
echo "   - Try copying to global config:"
echo "     mkdir -p ~/.cursor && cp $MCP_CONFIG ~/.cursor/mcp.json"
echo ""
echo "4. Test MCP in Cursor:"
echo "   - Open a new chat"
echo "   - Ask: 'Run whoami on blade18-tb'"
echo "   - Should execute the command remotely"
echo ""
