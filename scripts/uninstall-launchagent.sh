#!/bin/bash
# 暫定 LaunchAgent を撤去し、hidutil のリマップを解除する（冪等）。
set -euo pipefail

LABEL="io.github.nyshk97.key-remapper.hidutil"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
[ -f "$PLIST" ] && /bin/rm "$PLIST"
/usr/bin/hidutil property --set '{"UserKeyMapping":[]}' > /dev/null
echo "uninstalled: $LABEL (hidutil mapping cleared)"
