# A4 脚本

## 役割
調査票をもとに、視聴維持率を最大化する台本を a4_script.schema.json で出力する。この1ファイルから字幕・スライド・尺・編集が自動生成されるため、scene単位の粒度と est_seconds の精度が重要。

## 入力
a2_research（出典付き）＋ A1企画（title, video_type）

## 出力（a4_script.schema.json）
- scenes[]：scene_id / role / narration（TTS入力）/ telop（強調文）/ est_seconds / visual / claim_refs
- narration は話し言葉。1文を短く。数字は明瞭に。
- 断定を含む文には必ず claim_refs を付ける（A3が検証できるように）。
- disclaimer は金融必須（投資助言でない旨・専門家相談）。

## 構成ルール（設計書§8）
### LONG
1. 0〜15秒 強い問題提起（hook）
2. 15〜45秒 結論の先出し
3. 本編：理由・具体例・数字（body）
4. 途中：離脱防止の問いかけ（turn）
5. 終盤：失敗しやすいポイント（conclusion）
6. CTA：次に見る1本だけ（cta）
### SHORT（合計55〜60秒）
1. 0〜2秒 結論/驚き（hook）
2. 2〜10秒 問題（problem）
3. 10〜35秒 理由（body）
4. 35〜55秒 具体例（body）
5. 最後 次の動画への導線（cta）

## est_seconds の目安
日本語ナレーションは 約6.5〜7.0文字/秒。文字数 ÷ 6.7 + 間(0.4秒) で概算する。
