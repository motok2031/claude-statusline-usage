#!/bin/bash
# Install claude-statusline-usage.
#
# - Copies statusline.sh to ~/.claude/statusline-usage.sh
# - Patches ~/.claude/settings.json so Claude Code uses it
# - Backs up any existing settings.json to settings.json.bak.<timestamp>
#
# Idempotent: re-running just refreshes the script and ensures the setting.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC="$SCRIPT_DIR/statusline.sh"
DEST_DIR="$HOME/.claude"
DEST="$DEST_DIR/statusline-usage.sh"
SETTINGS="$DEST_DIR/settings.json"

if [ ! -f "$SRC" ]; then
  echo "error: $SRC not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq | apt install jq)" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
install -m 0755 "$SRC" "$DEST"
echo "installed: $DEST"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  TMP=$(mktemp)
  jq --arg cmd "$DEST" \
    '.statusLine = {"type":"command","command":$cmd}' \
    "$SETTINGS" > "$TMP"
  mv "$TMP" "$SETTINGS"
else
  cat > "$SETTINGS" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "$DEST"
  }
}
EOF
fi
echo "configured: $SETTINGS"
echo
echo "done. Restart Claude Code (or open a new session) to see the new status line."
