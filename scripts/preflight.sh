#!/bin/bash
# リリース前チェック。壊す前に（ビルドと Apple への submit の前に）全部検査する。
#
# release の最初と publish-release.sh の冒頭の両方から呼ぶ。publish の中だけに置くと、
# dirty worktree や未 push を検出する前に 5 分のビルドと notarize の submit が走ってしまう。
set -euo pipefail
cd "$(dirname "$0")/.."

GITHUB_REPO="nyshk97/keyrc"
VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*MARKETING_VERSION:[[:space:]]*//' | tr -d '"' | tr -d ' ')
TAG="v$VERSION"
[ -n "$VERSION" ] || { echo "NG: project.yml から MARKETING_VERSION を取れない"; exit 1; }

echo "preflight: $TAG をリリースする前提で検査する"

if ! gh auth status > /dev/null 2>&1; then
    echo "NG: gh が未認証（gh auth login）"; exit 1
fi

# 比較の前にリモートを取り込む。古い追跡参照と比べると「push 済みのつもり」を見逃す。
git fetch origin --tags --quiet

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "NG: カレントブランチが main でない（$BRANCH）"; exit 1
fi

# 未追跡ファイルも含めて見る。ビルド定義に追加済みの新規ソースが未追跡だと、
# 配布物には入るのにタグの commit には無いという乖離になる。
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
    echo "NG: 作業ツリーがクリーンでない（未追跡ファイルも対象）:"
    echo "$DIRTY"
    exit 1
fi

LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse origin/main)
if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
    echo "NG: HEAD が origin/main と一致しない（push 忘れ / pull 忘れ）"
    echo "    local:  $LOCAL_HEAD"
    echo "    origin: $REMOTE_HEAD"
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
    echo "NG: タグ $TAG が既にある（project.yml の MARKETING_VERSION を bump する）"; exit 1
fi

# gh の失敗は「Release が無い」と「通信エラー」を区別する。握りつぶすと既存 Release を
# 見逃して進み、公開済みバージョンを上書きしようとする。
if release_out=$(gh release view "$TAG" --repo "$GITHUB_REPO" 2>&1); then
    echo "NG: GitHub Release $TAG が既にある（project.yml の MARKETING_VERSION を bump する）"; exit 1
elif [ "$release_out" != "release not found" ]; then
    echo "NG: GitHub Release の確認に失敗した（通信エラー等。無いとは断定できない）:"
    echo "    $release_out"
    exit 1
fi

echo "preflight: OK（$TAG は未リリース。main / clean / push 済み）"
