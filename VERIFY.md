# 動作確認手順

## Layer 1 (hidutil)

### マッピングが適用されているか

```bash
hidutil property --get UserKeyMapping | grep -c HIDKeyboardModifierMappingSrc
# 期待値: 4（hyphen⇄quote, return⇄semicolon の双方向）
```

**注意: `--get` はプロパティを見ているだけで実効性を保証しない**（プロパティが載っていても効いていない事例あり）。
最終判定は必ず打鍵で行う: `-` で `'`、`;` で改行、Return で `;` が出れば OK。

### アプリ起動時・スリープ復帰時の Layer 1 適用

**「クリア → 即時再適用」は hidutil が実効しなくなることがある（実測）。クリアを挟む検証は必ず数秒空ける。**

```bash
tail /tmp/keyrc.log        # 本番（/Applications）
tail /tmp/keyrc-dev.log    # dev ビルド
# 起動直後・wake 直後に "hidutil: applied 4 mappings (exit 0)" が出ていれば OK
```

## メニューバー UI

System Events で自動操作できる（status item は **menu bar 1**。LSUIElement アプリなので menu bar 2 ではない点に注意）:

```bash
osascript <<'EOF'
tell application "System Events"
  tell process "keyrc"  # dev は "keyrc Dev"
    click menu bar item 1 of menu bar 1
    delay 0.3
    click menu item "一時停止" of menu 1 of menu bar item 1 of menu bar 1
  end tell
end tell
EOF
# ログで "paused" + "hidutil: cleared (paused)" を確認。「再開」「設定を再読み込み」も同様
```

## dev と本番の併存

- 本番: `/Applications/keyrc.app`（`io.github.nyshk97.keyrc` / Developer ID 署名 / SMAppService でログイン起動）
- dev: `mise run run` で起動（`io.github.nyshk97.keyrc.dev` / Apple Development 署名 / ログイン起動なし）
- TCC は別枠。dev で Layer 2 を検証するときはメニューから本番を「一時停止」する（hidutil は同値上書きなので併存可）

## Layer 2 (⌘単押し)

- 左⌘単押し → 英数、右⌘単押し → かな に切り替わること
- `⌘C` / `⌘クリック` / `⌘スクロール` で誤発火しないこと

## 全解除・フォールバック

Karabiner は 2026-08-16 にアンインストール済み（復帰先は無い）。

```bash
pkill -x keyrc                                    # Layer 2 停止
hidutil property --set '{"UserKeyMapping":[]}'    # Layer 1 クリア
# ログイン起動を止めるにはメニューバーから終了ではなく、アプリ削除 or System Settings → ログイン項目で OFF
```

keyrc が不調な場合の応急フォールバック:
- ⌘単押し: cmd-eikana は 2026-08-16 に削除済み。必要なら dominion525/cmd-eikana の配布バイナリ（署名・公証済み）を再導入する
- 記号スワップ: `./scripts/keyrc-apply` を手動実行（アプリなしでも hidutil は効く）

## リリース

手順は `keyremap-spec.md` の「次回以降のリリース手順」。確認ポイント:

- `python3 scripts/changelog.py check` が `[Unreleased]` 空なら exit 1（preflight のゲート）
- `RELEASE_VERSION=9.9.9 bash scripts/preflight.sh` で、ビルドせずに事前チェックだけ通せる（CHANGELOG が空のときはそこで止まる）
- dev 版の plist に feed が入っていないこと（入っていると dev が常用版のダウンロードで置き換わる）:
  `/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' 'build/Build/Products/Debug/keyrc Dev.app/Contents/Info.plist'` → 空文字
- リリース後: `gh release view v<ver> --repo nyshk97/keyrc --json body` が CHANGELOG の該当セクション、
  `curl -sL https://github.com/nyshk97/keyrc/releases/latest/download/appcast.xml` の `<description>` に同じ内容
