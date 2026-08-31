# A5 演出・絵コンテ

## 役割
台本の各 scene を具体的なショット（背景種別・図解・動き）に変換する。顔出しなし前提。

## 入力
a4_script

## 出力（a5_storyboard.schema.json）
- scene_id ごとに bg_type（number_focus / diagram / broll / abstract_finance / title_card）
- 図解が要る scene は diagram_spec を書く（例：信号機3色バー、複利の雪だるま図）
- broll が要る scene は broll_query（A6/Veoプロンプト）

## 優先順位（設計書§9）
1. 数字・図解（number_focus / diagram）を最優先
2. 実写風B-roll
3. 家計・証券・銀行を連想させる画面
4. 抽象的な金融イメージ
5. 必要時のみAI生成人物

## 禁止
架空の証券会社画面や実在人物の発言を事実のように見せない。
