# ⑤ Windows / VPS 上のフォルダ構成

n8n・Python・FFmpeg・Playwright が同じディスクを共有し、`YouTubeFactory/` を成果物のマスターにする。

## トップ階層（Windows例）

```
C:\YouTubeFactory\
├─ app\                         ← このリポジトリ (youtube-factory) を配置
│  ├─ schemas\                  ④ JSONスキーマ
│  ├─ prompts\                  ③ 各AIプロンプト
│  ├─ n8n\                      ② ワークフローJSON（インポート元）
│  ├─ automation\playwright\    ⑥ ブラウザ自動操作
│  └─ pipeline\                 ⑦ ローカル制作パイプライン(Python)
├─ jobs\                        ← EP単位の作業領域（設計書§10）
│  ├─ EP01\
│  │  ├─ research\   出典・調査票 (a2_research.json)
│  │  ├─ script\     台本 (a4_script.json)
│  │  ├─ voice\      ナレーション wav (EP01_SC001_NARRATION_V01.wav)
│  │  ├─ video\      映像素材/図解スライド (EP01_SC003_V01.mp4 / .png)
│  │  ├─ thumbnail\  サムネ (EP01_THUMB_V01.png)
│  │  ├─ subtitle\   字幕 (EP01.srt)
│  │  ├─ edit\       最終MP4 (EP01_FINAL_V01.mp4)
│  │  ├─ qa\         QAレポート (a10_qa.json)
│  │  └─ publish\    公開メタ (publish_metadata.json)
│  └─ EP02\ …
├─ bin\                         ← ffmpeg.exe / ffprobe.exe
├─ profiles\                    ← Chrome永続プロファイル（ログイン状態を保持）
│  ├─ chatgpt\  elevenlabs\  canva\  youtube\
├─ logs\                        ← n8n実行ログ・pipelineログ
└─ .env                         ← パス・チャンネルID等（機密はここだけ）
```

> 本リポジトリ内の `YouTubeFactory/EP01/` は、この `jobs\EP01\` と同じ構造の**PoC実物**（このリポジトリ内で完結させたサンプル）。本番では `C:\YouTubeFactory\jobs\` を使う。

## 命名規則（設計書§10）

| 種別 | 例 |
|------|----|
| scene映像 | `EP01_SC003_V01.mp4` |
| ナレーション(scene) | `EP01_SC001_NARRATION_V01.wav` |
| ナレーション(結合) | `EP01_NARRATION_V03.wav` |
| 字幕 | `EP01.srt` |
| サムネ | `EP01_THUMB_V01.png` |
| 最終動画 | `EP01_FINAL_V05.mp4` |

`V` は版数。差し戻し・再生成のたびにインクリメントし、旧版は消さず残す（監査用）。

## .env（例は .env.example 参照）

```
FACTORY_ROOT=C:\YouTubeFactory
JOBS_DIR=%FACTORY_ROOT%\jobs
FFMPEG=%FACTORY_ROOT%\bin\ffmpeg.exe
FFPROBE=%FACTORY_ROOT%\bin\ffprobe.exe
CHROME_PROFILE_DIR=%FACTORY_ROOT%\profiles
NOTION_DB_ID=798a4d93408f44b8a16acf9dde43c8fd
YOUTUBE_CHANNEL=（あなたのチャンネル）
```

## VPS運用の注意
- ブラウザ自動操作はGUIが要るため、VPSは「Windowsデスクトップが使えるVPS」または常時起動PCを推奨。
- ログイン状態は `profiles\` の永続プロファイルで維持（毎回ログインしない）。
- 機密（Cookie/プロファイル）はリポジトリに含めない（.gitignore 済）。
