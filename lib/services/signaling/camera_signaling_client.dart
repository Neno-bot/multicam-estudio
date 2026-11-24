import 'dart:async';
import 'dart:io';

import '../../core/models/signaling_message.dart';

class CameraSignalingClient {
  WebSocket? _socket;

  void Function(SignalingMessage message)? onMessage;
  void Function()? onDisconnected;

  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  Future<void> connect(String host, int port) async {
    await disconnect();
    _socket = await WebSocket.connect('ws://$host:$port')
        .timeout(const Duration(seconds: 5));

    _socket!.listen(
      (data) {
        if (data is! String) return;
        try {
          onMessage?.call(SignalingMessage.fromJsonString(data));
        } catch (_) {}
      },
      onDone: () => onDisconnected?.call(),
      onError: (_) => onDisconnected?.call(),
    );
  }

  void send(SignalingMessage message) {
    if (isConnected) {
      _socket!.add(message.toJsonString());
    }
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
}
