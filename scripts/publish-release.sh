#!/bin/bash
# notarize + staple 済みの dist/keyrc-<version>.zip を GitHub Release として公開する
# - Sparkle の EdDSA 署名を付けた appcast.xml を生成して同じ Release に添付する
# - SUFeedURL は releases/latest/download/appcast.xml（asset の実ファイル名で URL が決まる）
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/keyrc.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="dist/keyrc-$VERSION.zip"
SIGN_UPDATE="build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[ -f "$ZIP" ] || { echo "NG: $ZIP がない（先に mise run release-zip → notarize → staple）"; exit 1; }

# staple 済みかを検証（zip を展開して spctl で確認）
STAPLE_DIR=$(mktemp -d)
ditto -x -k "$ZIP" "$STAPLE_DIR"
assess=$(spctl --assess --type execute -vv "$STAPLE_DIR/keyrc.app" 2>&1)
if [[ "$assess" != *"Notarized Developer ID"* ]]; then
    echo "NG: notarize/staple されていない: $assess"; exit 1
fi
/bin/rm -rf "$STAPLE_DIR"

# EdDSA 署名（keychain の Sparkle 秘密鍵を使用）
ED_ATTRS=$("$SIGN_UPDATE" "$ZIP")   # 例: sparkle:edSignature="..." length="..."

PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/nyshk97/keyrc/releases/download/v$VERSION/keyrc-$VERSION.zip"

cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>keyrc</title>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="$DOWNLOAD_URL" $ED_ATTRS type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

gh release create "v$VERSION" "$ZIP" dist/appcast.xml \
    --title "keyrc v$VERSION" \
    --notes "https://github.com/nyshk97/keyrc/blob/main/keyremap-spec.md"

echo "OK: https://github.com/nyshk97/keyrc/releases/tag/v$VERSION"
