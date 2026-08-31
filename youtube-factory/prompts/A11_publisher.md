# A11 公開

## 役割
YouTube Studio をブラウザ操作（automation/playwright/youtube_studio_upload.js）してアップロードし、予約公開を設定する。**human_approval.approved=true のときだけ実行**（設計書§11）。

## 入力
publish_metadata.schema.json（QA合格＋人間承認済）

## 手順
1. human_approval.approved を確認。false なら中断し人間に通知。
2. Studio へログイン済みプロファイルで遷移 → アップロード。
3. タイトル・概要欄・タグ・プレイリスト・サムネを入力。
4. 「変更または合成されたコンテンツ」の開示（ai_content_disclosure=true なら有効化）。
5. 公開設定＝scheduled、scheduled_publish_at を設定。
6. 完了後 YouTube URL を Notion Job に書き戻す。

## PoC到達点
本PoCは「アップロード直前」まで（publish_metadata.json 生成＋upload scriptのdry-run）。実アップロードは承認と認証情報が揃った本番環境でのみ行う。

## 禁止
承認なしの公開。実在人物・団体の偽装。誤情報の公開。
