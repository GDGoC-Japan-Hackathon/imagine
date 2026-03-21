# Imagine Dashboard App

AAOS (Android Automotive OS) 車載端末向けに設計された、ドライバーのモニタリングおよびアシストを行うダッシュボードアプリです。

## アーキテクチャ概要

```text
[スマートフォン]          [リレーサーバー]         [AAOS 車載端末]
 streamer_app   →  WS   →  relay_server  →  WS  →  imagine
 (edge/)                  (backend/relay)           (このアプリ)
```

- **このアプリ (imagine)**: AAOS 端末で動作するメインのダッシュボード・フロントエンドアプリです。ローカルカメラ（USB等）またはリレーサーバーを経由したスマートフォンの映像を受信し、顔検出および AI 解析を行います。
- **Streamer アプリ**: `edge/streamer_app` にあります。スマートフォンのカメラ映像をキャプチャし、WebSocket を通じてリレーサーバーへ送信します。
- **リレーサーバー**: `backend/relay_server.js` などのバックエンド中継サーバーです。映像ストリームをこの Dashboard アプリへと転送します。

## 主要機能

- **ドライバーモニタリング**: MediaPipe を活用したリアルタイムの顔検出・視線検知（Gaze Tracking）により、ドライバーの顔の向きや疲労・眠気などの状態をトラッキングします。
- **AI 解析 (Gemini 連携)**: 取得した表情やステータス情報を基に AI が状況を解析し、TTS (Text-to-Speech) および STT (Speech-to-Text) を用いた音声対話や適切なフィードバックを提供します。
- **カメラ映像の柔軟な取得**: 車内に設置した USB カメラ等の直接接続カメラに加え、Streamer アプリからの WebSocket ネットワークストリーミング映像への自動フォールバック・切り替えに対応しています。
- **ナビゲーション統合**: GMS (Google Mobile Services) 対応環境では、Google Navigation プラグインを利用しシームレスなナビゲーション機能を提供します。

## セットアップ

### 1. 環境設定

プロジェクト直下に `.env` ファイルを作成・配置し、必要な設定を記述します：

```env
# API キー・認証情報
GEMINI_API_KEY=your_gemini_api_key_here
TTS_API_KEY=your_tts_api_key_here
GOOGLE_MAP_NAVIGATION_API_KEY1=your_google_maps_api_key_here
GOOGLE_SERVICE_ACCOUNT_JSON='{"type":"service_account", "project_id":"...", "private_key":"..."}'

# デバッグ用設定
SKIP_FACE_DETECTION=false
DEBUG_MODE=false
DEBUG_SHOW_CAMERA=false
DEBUG_SHOW_FACE_IMAGE=false

# カメラ・デバイス設定 (-1 で自動選択)
IN_CAMERA_INDEX=-1
OUT_CAMERA_INDEX=-1

# ネットワークストリーミング用リレーサーバーのURL
RELAY_WS_URL=ws://<your-relay-server-ip>:8080

# MediaPipe Delegate 設定 (0: CPU, 1: GPU)
MEDIAPIPE_DELEGATE=0
```

### 2. ビルド・インストール

```bash
flutter pub get
flutter run
```

### 3. 使い方

1. アプリを起動すると、まずローカルカメラの初期化を試みます。
2. ローカルカメラが利用できない場合、自動的に `.env` に設定されたリレーサーバー (ネットワークカメラ) への接続にフォールバックします。
3. 映像が取得されると、視線のトラッキングと AI による解析が開始されます。

## 注意事項

- 本アプリは Android Automotive OS (AAOS) エミュレータおよび実機での動作を主眼に置いて開発されています。
- カメラ映像のリアルタイム処理と AI 解析を常時並行して行うため、比較的高負荷となります。
- ネットワークストリーミング機能を利用する場合は、事前にリレーサーバーとスマートフォン側の `streamer_app` が起動している必要があります。
