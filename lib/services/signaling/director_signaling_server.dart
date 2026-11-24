import 'dart:async';
import 'dart:io';

import '../../core/constants/network_constants.dart';
import '../../core/models/signaling_message.dart';

class DirectorSignalingServer {
  HttpServer? _server;
  final Map<String, WebSocket> _cameraSockets = {};

  void Function(SignalingMessage message)? onMessage;
  void Function(String cameraId)? onCameraDisconnected;

  Future<void> start({int port = NetworkConstants.signalingPort}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleSocket(socket);
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('MultiCam Director Signaling Server OK')
          ..close();
      }
    });
  }

  void _handleSocket(WebSocket socket) {
    String? boundCameraId;

    void notifyDisconnect() {
      if (boundCameraId != null) {
        final removed = _cameraSockets.remove(boundCameraId);
        if (removed != null) {
          onCameraDisconnected?.call(boundCameraId!);
        }
      }
    }

    socket.listen(
      (data) {
        if (data is! String) return;
        try {
          final msg = SignalingMessage.fromJsonString(data);
          if (msg.type == 'register') {
            boundCameraId = msg.cameraId;
            _cameraSockets[msg.cameraId] = socket;
          }
          onMessage?.call(msg);
        } catch (_) {}
      },
      onDone: notifyDisconnect,
      onError: (_) => notifyDisconnect(),
    );
  }

  void sendToCamera(String cameraId, SignalingMessage message) {
    final socket = _cameraSockets[cameraId];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(message.toJsonString());
    }
  }

  /// Actualiza el estado Tally dual (EN VIVO rojo / PREVIO verde / STANDBY) en todas las cámaras
  void broadcastTally(String? liveCameraId, {String? previewCameraId}) {
    for (final cameraId in _cameraSockets.keys) {
      final isLive = cameraId == liveCameraId;
      final isPreview = !isLive && cameraId == previewCameraId;
      final state = isLive
          ? 'live'
          : isPreview
              ? 'preview'
              : 'standby';

      sendToCamera(
        cameraId,
        SignalingMessage(
          type: 'tally',
          cameraId: cameraId,
          payload: {
            'state': state,
            'isLive': isLive,
            'isPreview': isPreview,
          },
        ),
      );
    }
  }

  /// Envía un comando remoto a una cámara específica (ej: switch_camera, toggle_torch)
  void sendRemoteCommand(
    String cameraId,
    String action, {
    Map<String, dynamic> params = const {},
  }) {
    sendToCamera(
      cameraId,
      SignalingMessage(
        type: 'command',
        cameraId: cameraId,
        payload: {'action': action, ...params},
      ),
    );
  }

  Future<void> stop() async {
    for (final socket in _cameraSockets.values) {
      await socket.close();
    }
    _cameraSockets.clear();
    await _server?.close(force: true);
    _server = null;
  }
}
