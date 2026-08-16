#!/bin/bash
# 署名証明書のハッシュはマシンごとに異なるため、project.yml に直書きせず
# keychain から検出して gitignore 対象の *.local.xcconfig に書き出す。
# ハッシュ固定の目的（TCC 権限の安定）は各マシン内で保たれる。
set -euo pipefail
cd "$(dirname "$0")/.."

ids=$(security find-identity -v -p codesigning)
debug_hash=$(echo "$ids" | awk '/"Apple Development/ {print $2; exit}')
release_hash=$(echo "$ids" | awk '/"Developer ID Application/ {print $2; exit}')

# 同一内容の上書きをしない（xcconfig の mtime 更新で全リビルドが走るのを防ぐ）
write_if_changed() {
  local path=$1 content=$2
  if [ ! -f "$path" ] || [ "$(cat "$path")" != "$content" ]; then
    printf '%s\n' "$content" > "$path"
    echo "signing: $path を更新した"
  fi
}

header="// scripts/gen-signing-xcconfig.sh が生成（マシン固有・コミットしない）"

if [ -n "$debug_hash" ]; then
  write_if_changed signing-debug.local.xcconfig "$header
CODE_SIGN_IDENTITY = $debug_hash"
else
  write_if_changed signing-debug.local.xcconfig "$header
// Apple Development 証明書が keychain に無いため未設定"
  echo "signing: 警告: Apple Development 証明書が見つからない（Debug ビルドは署名で失敗する）" >&2
fi

if [ -n "$release_hash" ]; then
  write_if_changed signing-release.local.xcconfig "$header
CODE_SIGN_IDENTITY = $release_hash"
else
  write_if_changed signing-release.local.xcconfig "$header
// Developer ID Application 証明書が keychain に無いため未設定"
  echo "signing: 警告: Developer ID Application 証明書が見つからない（Release ビルドは署名で失敗する）" >&2
fi
