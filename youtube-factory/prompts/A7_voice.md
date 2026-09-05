# A7 音声（ナレーション）

## 役割
台本の narration を自然な日本語ナレーション音声にする。Higgsfield MCP（またはElevenLabs等のWeb UIブラウザ操作）を使う。scene単位でwavを書き出し、pipeline が尺を実測してタイムラインを確定する。

## 入力
a4_script（scenes[].tts_prompt。未設定なら `pipeline/lib/tts_lint.build_tts_prompt(narration)` で自動生成される）

## 出力
- `YouTubeFactory/EP01/voice/EP01_SC001_NARRATION_V01.wav` … scene単位
- 命名規則：`EP01_NARRATION_V03.wav`（結合版。ただし下記の理由で「生成」は結合版で行わない）

## 【必須ルール】1回のTTS呼び出しは1シーン分の短文だけ

**複数シーンを連結した長文を1回のTTS呼び出しで生成することを禁止する。**
検証の結果、長文を一括生成すると、モデルが確率的に日本語以外の音や
ノイズ的なアーティファクトを混入させることを確認した。scene単位（短文）
で個別に生成し、後段の編集（A9）で結合すること。「レビュー用に1本にまとめて
聴きたい」場合も、まずscene単位で生成し、結合はローカルのffmpegで行う。

## 発音（誤読対策）は `tts_prompt` を使う

`narration`（画面表示・字幕用の正しい漢字表記）をそのままTTSに渡さない。
必ず `tts_prompt`（`tts_lint.py`が自動生成する開き読みテキスト）を使う。
これにより「十八→じゅうばち」「貯金→じょきん」のような、TTSのG2P誤変換に
起因する誤読を、人手の目視チェックに頼らず構造的に防ぐ。

新しい誤読が見つかったら：
1. 数字が原因なら `pipeline/lib/tts_numbers.py` のロジックを疑う（通常は既に正しく変換されているはず）。
2. 専門用語（漢字の同形異読）が原因なら `pipeline/lib/tts_homographs.json` に語を追加する。
3. ひらがな表記に直しても直らない場合（エンジン自体の音響的な癖）は、
   カタカナ表記や別エンジン（seed_speech等）へのフォールバックを試し、
   有効だった対策を `docs/07_tts_quality_gate.md` に追記する。

詳細は `docs/07_tts_quality_gate.md` を参照。

## 声・話し方
- 落ち着いた信頼感のある声。速度は等倍（不自然な高速化は明瞭さを損なうため避ける）。
- 数字・期限・金額は明瞭に区切って読む。
- SHORTは冒頭2秒でフックが刺さるテンポ。

## 生成後の必須チェック（自動）
`run_ep01.py --stage build` は、実ナレーションが `voice/` にある場合、
`tts_lint.check_duration_anomaly` で「文字数から想定される尺」と「実測の尺」を
突き合わせる。乖離が大きい（ノイズ混入・幻聴的アーティファクトの疑い）場合は
buildを例外で停止し、最終動画に焼き込まない。結果は
`qa/EP{ep}_voice_anomaly_report.json` に保存される。

## PoCでの扱い
音声未生成の状態では `pipeline/lib/tts_stub.py` が est_seconds 通りの
無音トラックを生成し、編集・字幕同期を検証する。実際のwavを voice/ に
置けば pipeline が自動で差し替え、異常検知も有効になる。
