const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 }); // Fixed syntax: port 8080 -> port: 8080

console.log('--- WebSocket Relay Server Started on 8080 ---');

wss.on('connection', (ws) => { // Fixed syntax: = -> =>
    console.log('A client (Dashboard or Streamer) connected.'); // Updated message
    
    ws.on('message', (message, isBinary) => { // Fixed syntax: = -> =>, added isBinary
        // デバッグ用ログ: コマンド文字列か画像バイナリかを判別
        if (!isBinary) {
            console.log('--- COMMAND RECEIVED ---');
            console.log('Content:', message.toString());
        } else {
            // 画像データ（バイナリ）の場合は頻度が高いので、数秒おきにのみログ出力
        }

        // 全員（自分以外）に受信データをそのまま転送
        wss.clients.forEach((client) => {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
                client.send(message, { binary: isBinary }); // Added { binary: isBinary }
            }
        });
    });
    
    ws.on('close', () => console.log('A client disconnected.')); // Fixed syntax: = -> =>
});