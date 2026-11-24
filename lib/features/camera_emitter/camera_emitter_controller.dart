import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/signaling_message.dart';
import '../../core/models/video_quality_profile.dart';
import '../../services/discovery/local_discovery_service.dart';
import '../../services/signaling/camera_signaling_client.dart';
import '../../services/webrtc/camera_webrtc_service.dart';

enum EmitterStatus {
  initializing,
  searchingDirector,
  connecting,
  streamingStandby,
  streamingPreview,
  streamingLive,
  error,
}

class CameraEmitterController extends ChangeNotifier {
  final LocalDiscoveryService _discovery = LocalDiscoveryService();
  final CameraSignalingClient _signaling = CameraSignalingClient();
  final CameraWebRTCService _webrtc = CameraWebRTCService();

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final String cameraId = const Uuid().v4();
  late String cameraName;

  StreamSubscription<DiscoveredDirector>? _discoverySub;
  DiscoveredDirector? _connectedDirector;
  EmitterStatus _status = EmitterStatus.initializing;
  String? _statusDetail;
  bool _isConnectingToDirector = false;
  bool _isDisposed = false;

  EmitterStatus get status => _status;
  String? get statusDetail => _statusDetail;
  DiscoveredDirector? get connectedDirector => _connectedDirector;
  bool get isFrontCamera => _webrtc.isFrontCamera;
  bool get isMuted => _webrtc.isMuted;
  bool get isTorchOn => _webrtc.isTorchOn;
  VideoQualityProfile get qualityProfile => _webrtc.qualityProfile;
  bool get isLiveOnAir => _status == EmitterStatus.streamingLive;
  bool get isPreviewReady => _status == EmitterStatus.streamingPreview;

  CameraEmitterController() {
    final suffix = cameraId.substring(0, 4).toUpperCase();
    cameraName = '${Platform.isIOS ? "iPhone" : "Android"} $suffix';
  }

  Future<void> initialize() async {
    await WakelockPlus.enable();
    await localRenderer.initialize();

    try {
      final stream = await _webrtc.initLocalMedia();
      if (_isDisposed) return;
      localRenderer.srcObject = stream;
      _setStatus(
        EmitterStatus.searchingDirector,
        'Buscando Director en Wi-Fi...',
      );
      await _startDiscovery();
    } catch (e) {
      _setStatus(EmitterStatus.error, 'Error de cámara: $e');
    }
  }

  Future<void> _startDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = _discovery.onDirectorFound.listen((director) {
      if (!_isDisposed &&
          _connectedDirector == null &&
          !_isConnectingToDirector) {
        _connectToDirector(director);
      }
    });
    await _discovery.startDiscoveringDirector();
  }

  /// Conexión directa mediante IP/Puerto manual o código QR
  Future<void> connectManually({
    required String host,
    required int port,
    String? newCameraName,
  }) async {
    if (newCameraName != null && newCameraName.trim().isNotEmpty) {
      cameraName = newCameraName.trim();
    }

    _connectedDirector = null;
    await _signaling.disconnect();
    await _webrtc.closePeerConnection();

    await _connectToDirector(
      DiscoveredDirector(host: host, port: port, name: 'Director ($host)'),
    );
  }

  /// Renombra la cámara y sincroniza el nombre con el Director
  void updateCameraName(String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    cameraName = trimmed;
    if (_signaling.isConnected) {
      _signaling.send(
        SignalingMessage(
          type: 'rename',
          cameraId: cameraId,
          payload: {'name': cameraName},
        ),
      );
    }
    _safeNotify();
  }

  /// Fase 3: Cambia el perfil de resolución/bitrate en vivo (480p / 720p / 1080p)
  Future<void> setVideoQuality(VideoQualityProfile profile) async {
    try {
      final updatedStream = await _webrtc.changeVideoQuality(profile);
      if (_isDisposed) return;
      if (updatedStream != null) {
        localRenderer.srcObject = updatedStream;
      }
      _sendDeviceState();
      _safeNotify();
    } catch (_) {}
  }

  Future<void> _connectToDirector(DiscoveredDirector director) async {
    _isConnectingToDirector = true;
    _setStatus(
      EmitterStatus.connecting,
      'Conectando a ${director.name} (${director.host})...',
    );

    _signaling.onMessage = _handleSignalingMessage;
    _signaling.onDisconnected = _handleDirectorDisconnected;

    try {
      await _signaling.connect(director.host, director.port);
      if (_isDisposed) return;
      _connectedDirector = director;

      // 1. Registrar cámara en la Tablet Director
      _signaling.send(
        SignalingMessage(
          type: 'register',
          cameraId: cameraId,
          payload: {
            'name': cameraName,
            'quality': _webrtc.qualityProfile.id,
          },
        ),
      );

      // 2. Crear oferta WebRTC y enviarla
      final offer = await _webrtc.createOffer(
        onIceCandidate: (candidate) {
          _signaling.send(
            SignalingMessage(
              type: 'ice_candidate',
              cameraId: cameraId,
              payload: {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            ),
          );
        },
        onConnectionState: (state) {
          if (_isDisposed) return;
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            if (_status != EmitterStatus.streamingLive &&
                _status != EmitterStatus.streamingPreview) {
              _setStatus(
                EmitterStatus.streamingStandby,
                'Conectado a ${director.name}',
              );
            }
          } else if (state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            _handleDirectorDisconnected();
          }
        },
      );

      _signaling.send(
        SignalingMessage(
          type: 'offer',
          cameraId: cameraId,
          payload: {'sdp': offer.sdp, 'sdpType': offer.type},
        ),
      );
    } catch (_) {
      _connectedDirector = null;
      _setStatus(
        EmitterStatus.searchingDirector,
        'No se pudo conectar. Buscando Director...',
      );
    } finally {
      _isConnectingToDirector = false;
    }
  }

  Future<void> _handleSignalingMessage(SignalingMessage msg) async {
    if (_isDisposed) return;
    switch (msg.type) {
      case 'answer':
        await _webrtc.setRemoteAnswer(
          msg.payload['sdp'] as String,
          msg.payload['sdpType'] as String,
        );
        break;
      case 'ice_candidate':
        await _webrtc.addIceCandidate(msg.payload);
        break;
      case 'tally':
        final isLive = msg.payload['isLive'] == true ||
            msg.payload['state'] == 'live';
        final isPreview = !isLive &&
            (msg.payload['isPreview'] == true ||
                msg.payload['state'] == 'preview');

        if (isLive) {
          _setStatus(
            EmitterStatus.streamingLive,
            'AL AIRE EN MONITOR PRINCIPAL',
          );
        } else if (isPreview) {
          _setStatus(
            EmitterStatus.streamingPreview,
            'EN PREVIO (PVW) — PREPÁRATE',
          );
        } else {
          _setStatus(
            EmitterStatus.streamingStandby,
            'En espera (Standby)',
          );
        }
        break;
      case 'command':
        await _handleRemoteCommand(msg.payload);
        break;
      case 'error':
        _setStatus(
          EmitterStatus.error,
          (msg.payload['message'] as String?) ?? 'Rechazado por el Director',
        );
        break;
    }
  }

  Future<void> _handleRemoteCommand(Map<String, dynamic> payload) async {
    final action = payload['action'] as String?;
    switch (action) {
      case 'switch_camera':
        await switchCamera();
        break;
      case 'toggle_torch':
        await toggleTorch();
        break;
      case 'set_quality':
        final profile = VideoQualityProfile.fromId(
          payload['quality'] as String?,
        );
        await setVideoQuality(profile);
        break;
    }
  }

  void _handleDirectorDisconnected() {
    if (_isDisposed || _connectedDirector == null) return;
    _connectedDirector = null;
    _webrtc.closePeerConnection();
    _setStatus(
      EmitterStatus.searchingDirector,
      'Director desconectado. Buscando nuevamente...',
    );
  }

  Future<void> switchCamera() async {
    await _webrtc.switchCamera();
    _sendDeviceState();
    _safeNotify();
  }

  Future<void> toggleTorch() async {
    await _webrtc.toggleTorch();
    _sendDeviceState();
    _safeNotify();
  }

  void toggleMute() {
    _webrtc.toggleMute();
    _safeNotify();
  }

  void _sendDeviceState() {
    if (!_signaling.isConnected) return;
    _signaling.send(
      SignalingMessage(
        type: 'device_state',
        cameraId: cameraId,
        payload: {
          'isTorchOn': _webrtc.isTorchOn,
          'quality': _webrtc.qualityProfile.id,
        },
      ),
    );
  }

  void _setStatus(EmitterStatus newStatus, [String? detail]) {
    _status = newStatus;
    _statusDetail = detail;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WakelockPlus.disable();
    _discoverySub?.cancel();
    _discovery.dispose();
    _signaling.disconnect();
    _webrtc.dispose();
    localRenderer.srcObject = null;
    localRenderer.dispose();
    super.dispose();
  }
}
