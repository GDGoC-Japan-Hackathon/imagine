import 'dart:io';

final List<WebSocket> clients = [];

void main() async {
  final portStr = Platform.environment['PORT'] ?? '8080';
  final port = int.parse(portStr);
  
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('WebSocket Relay Server listening on port ${server.port}...');

  await for (HttpRequest request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocket ws = await WebSocketTransformer.upgrade(request);
      clients.add(ws);
      print('Client connected. Total clients: ${clients.length}');

      ws.listen(
        (data) {
          // Broadcast data to all OTHER connected clients
          for (var client in clients) {
            if (client != ws && client.readyState == WebSocket.open) {
              client.add(data);
            }
          }
        },
        onDone: () {
          clients.remove(ws);
          print('Client disconnected. Total clients: ${clients.length}');
        },
        onError: (error) {
          clients.remove(ws);
          print('Client error: $error');
        },
      );
    } else {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('WebSocket connections only')
        ..close();
    }
  }
}
