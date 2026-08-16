# 動作確認手順

## Layer 1 (hidutil)

### マッピングが適用されているか

```bash
hidutil property --get UserKeyMapping | grep -c HIDKeyboardModifierMappingSrc
# 期待値: 4（hyphen⇄quote, return⇄semicolon の双方向）
```

打鍵確認: `-` で `'`、`;` で改行、Return で `;` が出れば OK。

### LaunchAgent の適用フロー（end-to-end）

```bash
hidutil property --set '{"UserKeyMapping":[]}'   # 一旦クリア
./scripts/install-launchagent.sh                  # RunAtLoad で再適用される
hidutil property --get UserKeyMapping | grep -c HIDKeyboardModifierMappingSrc  # → 4
launchctl print "gui/$(id -u)/io.github.nyshk97.key-remapper.hidutil" | grep 'last exit'  # → 0
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
