#!/bin/bash
# Release ビルドを配布適格に再署名して dist/keyrc-<version>.zip を作る
#
# 背景: xcodebuild build は埋め込んだ Sparkle.framework の外側しか再署名せず、
# 内部の XPC サービス等が adhoc 署名のまま残り notarization が Invalid になる。
# ここで inside-out に Developer ID + timestamp で署名し直す。
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="85D91870B2836DB303E2224A2D8D56051F26A6FB" # Developer ID Application: Tsubasa Namatame
APP="build/Build/Products/Release/keyrc.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

mise run build-release >/dev/null

# inside-out: ネストの深いバイナリから順に署名する
# Sparkle の XPC はエンタイトルメントを持つため --preserve-metadata=entitlements で維持する
for nested in \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/Updater.app" \
    "$SPARKLE/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements --sign "$IDENTITY" "$nested"
done
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

# 検証: adhoc が残っていないこと・secure timestamp があること・get-task-allow がないこと
fail=0
for target in \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/Updater.app" \
    "$SPARKLE/Autoupdate" \
    "$APP/Contents/Frameworks/Sparkle.framework" \
    "$APP"; do
    info=$(codesign -dvv "$target" 2>&1)
    if [[ "$info" == *"Signature=adhoc"* ]]; then
        echo "NG: adhoc署名が残存: $target"; fail=1
    fi
    if [[ "$info" != *"Timestamp="* ]]; then
        echo "NG: secure timestampなし: $target"; fail=1
    fi
done
ent=$(codesign -d --entitlements - "$APP" 2>&1)
if [[ "$ent" == *"get-task-allow"* ]]; then
    echo "NG: get-task-allow が残存"; fail=1
fi
codesign --verify --deep --strict "$APP" || fail=1
[ "$fail" -eq 0 ] || exit 1

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
ZIP="dist/keyrc-$VERSION.zip"
/bin/rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "OK: $ZIP"
echo "次: xcrun notarytool submit \"$ZIP\" --keychain-profile <プロファイル名> --wait"
echo "    → Accepted 後: ditto -x -k \"$ZIP\" /tmp/staple && xcrun stapler staple /tmp/staple/keyrc.app"
echo "      再zip: ditto -c -k --sequesterRsrc --keepParent /tmp/staple/keyrc.app \"$ZIP\""
