# A6 映像

## 役割
絵コンテの broll_query / diagram_spec を映像素材に変換。Veo等のWeb UIをブラウザ操作（automation/playwright）で使う。図解はローカル生成（pipeline/lib/slides.py）を優先し、確実性を担保する。

## 入力
a5_storyboard

## 出力
- 素材ファイル：`YouTubeFactory/EP01/video/EP01_SC003_V01.mp4` 等（命名規則は docs/05）
- 生成できない/規約上不可の scene はローカルのスライド（number_focus/diagram）で代替

## Veoプロンプト方針
- 顔出しなし・実在ブランド不使用・実在人物の発言を装わない
- 金融の抽象イメージ（グラフ、コイン、通帳の質感）に留める
- 各クリップは scene の est_seconds 以上の長さで生成

## 注意
Web UIの自動操作は各サービスの利用規約・自動化制限に従う。生成不可なら図解フォールバックに切替（品質より確実性を優先）。
