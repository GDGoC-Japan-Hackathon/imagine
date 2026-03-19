const WebSocket = require('ws');
const wss = new WebSocket.Server({ port 8080 });

console.log('--- WebSocket Relay Server Started on 8080 ---');

wss.on('connection', (ws) = {
    console.log('A client connected.');
    ws.on('message', (message) = {
         全員（自分以外）に受信データをそのまま転送
        wss.clients.forEach((client) = {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
                client.send(message);
            }
        });
    });
    ws.on('close', () = console.log('A client disconnected.'));
});