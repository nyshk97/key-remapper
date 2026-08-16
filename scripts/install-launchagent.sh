#!/bin/bash
# M1 の暫定 LaunchAgent をインストールする（冪等）。
# ログイン時に hidutil リマップを適用する。
# 注意: launchd 起動のプロセスは TCC の制約で ~/.config 配下の CloudStorage symlink を
# 読めないため、インストール時に設定を解決して hidutil の引数として plist に焼き込む。
# 設定変更後はこのスクリプトを再実行すること。
# M3 で常駐アプリに統合されたら uninstall-launchagent.sh で撤去する。
set -euo pipefail

LABEL="io.github.nyshk97.key-remapper.hidutil"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APPLY_SCRIPT="$(cd "$(dirname "$0")" && pwd)/key-remapper-apply"
PAYLOAD="$("$APPLY_SCRIPT" --print)"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>$PAYLOAD</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/key-remapper-hidutil.log</string>
    <key>StandardOutPath</key>
    <string>/tmp/key-remapper-hidutil.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed and loaded: $LABEL"
