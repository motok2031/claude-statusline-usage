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

PYTHON=${CSU_PYTHON:-python3}
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "error: python3 is required (it's pre-installed on macOS via Xcode CLT and on most Linux distros)" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
install -m 0755 "$SRC" "$DEST"
echo "installed: $DEST"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  TMP=$(mktemp)
  "$PYTHON" -c '
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
data["statusLine"] = {"type": "command", "command": cmd}
print(json.dumps(data, indent=2, ensure_ascii=False))
' "$SETTINGS" "$DEST" > "$TMP"
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
