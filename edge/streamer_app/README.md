# Imagine Streamer App

スマートフォンのカメラ映像を WebSocket 経由でリレーサーバーに中継する専用アプリです。

## アーキテクチャ概要

```
[スマートフォン]          [リレーサーバー]         [AAOS 車載端末]
 streamer_app   →  WS   →  relay_server  →  WS  →  flutter_application_screen
 (このアプリ)             (backend/relay)           (frontend/)
```

- **このアプリ (streamer_app)**: スマートフォンのカメラ映像をキャプチャし、WebSocket でリレーサーバーへ送信します。
- **リレーサーバー**: `backend/relay_server.js` にあります。Google Cloud VM などで常時起動させてください。
- **Dashboard アプリ**: `frontend/flutter_application_screen` が AAOS 端末で動作します。リレーサーバー経由でこのアプリの映像を受信し、顔検出・AI 解析を行います。

## セットアップ

### 1. 環境設定

`.env` ファイルを編集してリレーサーバーの URL を設定します：

```env
RELAY_WS_URL = ws://<your-relay-server-ip>:8080
```

### 2. ビルド・インストール

```bash
flutter pub get
flutter run
```

### 3. 使い方

1. アプリを起動すると自動的にカメラが起動し、リレーサーバーへの接続を試みます。
2. 画面に「接続済み」と表示されれば映像の中継が開始されます。
3. AAOS 側 (Dashboard アプリ) で顔検出が有効になると、このアプリのカメラが利用されます。
4. Dashboard 側からカメラ切り替えコマンドが届いた際、フロント↔バックカメラを切り替えます。

## 注意事項

- このアプリは Streamer（映像中継）機能のみを担当します。AI 解析や Dashboard UI は含みません。
- Android のカメラパーミッション (`CAMERA`) とインターネットアクセス (`INTERNET`) が必要です。
- 常時カメラ・ネットワークを使用するため、バッテリー消耗が大きくなります。充電しながらの使用を推奨します。
