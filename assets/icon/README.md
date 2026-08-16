# アプリアイコン

- `icon.svg` — ソース（512 座標系・フルブリード。角丸マスクは macOS 26+ が付与する）
- `icon-1024.png` — マスター PNG（icon.svg をブラウザ canvas で 1024px にラスタライズしたもの）

## 再生成手順

1. `icon.svg` を編集する
2. ブラウザで SVG を 1024x1024 の canvas に描画して PNG 化する
   （SVG を `<img>` で読み込み `drawImage` → `canvas.toDataURL`。テキストは
   -apple-system を参照しているため macOS 上のブラウザでラスタライズすること）
3. `Sources/Assets.xcassets/AppIcon.appiconset/` の各サイズを更新する:

```sh
cd Sources/Assets.xcassets/AppIcon.appiconset
for s in 16 32 64 128 256 512; do
  sips -z $s $s ../../../assets/icon/icon-1024.png --out icon_${s}.png
done
cp ../../../assets/icon/icon-1024.png icon_1024.png
```

## デザインメモ

- 案は「キー・スワップ」: `⌘` と `あ` のキーキャップ（⌘単押しのかな切替＝中心機能）を循環矢印で入れ替え
- 背景は #4a7dfc → #7a3ff2 の斜めグラデーション
- deploymentTarget が macOS 13 のため、macOS 25 以前では角丸なしの四角で表示される（許容済み）
