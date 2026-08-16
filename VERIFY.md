# 動作確認手順

## Layer 1 (hidutil)

### マッピングが適用されているか

```bash
hidutil property --get UserKeyMapping | grep -c HIDKeyboardModifierMappingSrc
# 期待値: 4（hyphen⇄quote, return⇄semicolon の双方向）
```

**注意: `--get` はプロパティを見ているだけで実効性を保証しない**（プロパティが載っていても効いていない事例あり）。
最終判定は必ず打鍵で行う: `-` で `'`、`;` で改行、Return で `;` が出れば OK。

### LaunchAgent の適用フロー（end-to-end）

**「クリア → 即時再適用」は hidutil が実効しなくなることがある（実測）。クリア後は必ず数秒空ける。**

```bash
hidutil property --set '{"UserKeyMapping":[]}'   # 一旦クリア
sleep 3                                           # 即時再適用を避ける（必須）
./scripts/install-launchagent.sh                  # RunAtLoad で再適用される
launchctl print "gui/$(id -u)/io.github.nyshk97.key-remapper.hidutil" | grep 'last exit'  # → 0
# 最後に必ず打鍵確認（上記）
```

### アプリ起動時・スリープ復帰時の Layer 1 適用

```bash
tail /tmp/key-remapper.log
# 起動直後・wake 直後に "hidutil: applied 4 mappings (exit 0)" が出ていれば OK
```

## Layer 2 (⌘単押し)

- 左⌘単押し → 英数、右⌘単押し → かな に切り替わること
- `⌘C` / `⌘クリック` / `⌘スクロール` で誤発火しないこと

## 全解除・復元（M0 検証期間中）

```bash
./scripts/uninstall-launchagent.sh                # LaunchAgent 撤去 + hidutil クリア
'/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli' \
  --select-profile 'Default profile'              # Karabiner の元設定に復帰
```
