import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/network_constants.dart';
import '../../core/models/camera_node.dart';
import '../../core/models/overlay_config.dart';
import '../../core/models/signaling_message.dart';
import '../../core/models/video_quality_profile.dart';
import '../../services/discovery/local_discovery_service.dart';
import '../../services/recording/program_recorder_service.dart';
import '../../services/signaling/director_signaling_server.dart';
import '../../services/webrtc/director_webrtc_service.dart';

class DirectorController extends ChangeNotifier {
  final LocalDiscoveryService _discovery = LocalDiscoveryService();
  final DirectorSignalingServer _signaling = DirectorSignalingServer();
  final DirectorWebRTCService _webrtc = DirectorWebRTCService();
  final ProgramRecorderService _recorder = ProgramRecorderService();

  /// Renderer exclusivo del Monitor Principal EN VIVO (PGM)
  final RTCVideoRenderer programRenderer = RTCVideoRenderer();

  /// Fase 3: Renderer exclusivo del Monitor PREVIO (PVW) en Modo Estudio
  final RTCVideoRenderer previewRenderer = RTCVideoRenderer();

  /// 4 slots fijos para la cuadrícula inferior (índices 0..3)
  final List<CameraNode?> slots = List<CameraNode?>.filled(
    NetworkConstants.maxConnectedCameras,
    null,
  );

  String? _activeLiveCameraId;
  String? _previewCameraId;
  String _localIp = '...';
  bool _isRunning = false;
  bool _isDisposed = false;

  // Fase 2: Audio Follows Video (AFV), Transiciones, Overlays y Grabación
  bool _audioFollowsVideo = true;
  TransitionMode _transitionMode = TransitionMode.cut;
  bool _isFadingTransition = false;
  OverlayConfig _overlayConfig = const OverlayConfig();

  // Fase 3: Modo Estudio (PVW/PGM + TAKE) y Telemetría WebRTC
  bool _studioMode = false;
  bool _showTelemetry = true;
  Timer? _telemetryTimer;

  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  String? _lastError;

  String? get activeLiveCameraId => _activeLiveCameraId;
  String? get previewCameraId => _previewCameraId;
  String get localIp => _localIp;
  bool get isRunning => _isRunning;
  bool get audioFollowsVideo => _audioFollowsVideo;
  TransitionMode get transitionMode => _transitionMode;
  bool get isFadingTransition => _isFadingTransition;
  OverlayConfig get overlayConfig => _overlayConfig;
  bool get studioMode => _studioMode;
  bool get showTelemetry => _showTelemetry;
  bool get isRecording => _recorder.isRecording;
  Duration get recordingDuration => _recordingDuration;
  String? get lastError => _lastError;

  int get connectedCount => slots.where((s) => s != null).length;

  CameraNode? get activeLiveCamera => _findNodeById(_activeLiveCameraId);
  CameraNode? get previewCamera => _findNodeById(_previewCameraId);

  bool get canTake =>
      _studioMode &&
      previewCamera != null &&
      previewCamera!.stream != null &&
      previewCamera!.id != _activeLiveCameraId;

  /// Indica si el audio de una cámara está sonando actualmente en mezcla
  bool isCameraAudioActive(CameraNode node) {
    if (node.isAudioMuted) return false;
    if (_audioFollowsVideo) return node.id == _activeLiveCameraId;
    return true;
  }

  Future<void> initialize() async {
    await WakelockPlus.enable();
    await programRenderer.initialize();
    await previewRenderer.initialize();

    _signaling.onMessage = _handleSignalingMessage;
    _signaling.onCameraDisconnected = _removeCamera;

    await _signaling.start(port: NetworkConstants.signalingPort);
    _localIp = await _discovery.startAdvertisingDirector(
      signalingPort: NetworkConstants.signalingPort,
    );

    _startTelemetryPolling();
    _isRunning = true;
    _safeNotify();
  }

  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_isDisposed || !_showTelemetry) return;
      bool updated = false;
      for (final slot in slots) {
        if (slot == null || slot.stream == null) continue;
        final stats = await _webrtc.getCameraStats(slot.id);
        if (_isDisposed) return;
        if (stats != null) {
          slot.stats = stats;
          updated = true;
        }
      }
      if (updated) _safeNotify();
    });
  }

  Future<void> _handleSignalingMessage(SignalingMessage msg) async {
    if (_isDisposed) return;
    switch (msg.type) {
      case 'register':
        await _registerCamera(
          msg.cameraId,
          (msg.payload['name'] as String?) ?? 'Cámara',
          quality: VideoQualityProfile.fromId(msg.payload['quality'] as String?),
        );
        break;

      case 'rename':
        final node = _findNodeById(msg.cameraId);
        final newName = (msg.payload['name'] as String?)?.trim();
        if (node != null && newName != null && newName.isNotEmpty) {
          node.name = newName;
          _safeNotify();
        }
        break;

      case 'device_state':
        final node = _findNodeById(msg.cameraId);
        if (node != null) {
          if (msg.payload.containsKey('isTorchOn')) {
            node.isTorchOn = msg.payload['isTorchOn'] == true;
          }
          if (msg.payload.containsKey('quality')) {
            node.quality =
                VideoQualityProfile.fromId(msg.payload['quality'] as String?);
          }
          _safeNotify();
        }
        break;

      case 'offer':
        await _handleOffer(msg);
        break;

      case 'ice_candidate':
        await _webrtc.addIceCandidate(msg.cameraId, msg.payload);
        break;
    }
  }

  Future<void> _registerCamera(
    String cameraId,
    String name, {
    VideoQualityProfile quality = VideoQualityProfile.hd720p,
  }) async {
    if (slots.any((s) => s?.id == cameraId)) return;

    final emptySlotIndex = slots.indexWhere((s) => s == null);
    if (emptySlotIndex == -1) {
      _signaling.sendToCamera(
        cameraId,
        SignalingMessage(
          type: 'error',
          cameraId: cameraId,
          payload: {'message': 'Máximo de 4 cámaras alcanzado'},
        ),
      );
      return;
    }

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    if (_isDisposed) {
      await renderer.dispose();
      return;
    }

    slots[emptySlotIndex] = CameraNode(
      id: cameraId,
      name: name,
      slotIndex: emptySlotIndex,
      renderer: renderer,
      status: CameraConnectionState.connecting,
      quality: quality,
    );
    _safeNotify();
  }

  Future<void> _handleOffer(SignalingMessage msg) async {
    final cameraNode = _findNodeById(msg.cameraId);
    if (cameraNode == null) return;

    final answer = await _webrtc.handleCameraOffer(
      cameraId: msg.cameraId,
      sdp: msg.payload['sdp'] as String,
      sdpType: msg.payload['sdpType'] as String,
      onIceCandidate: (candidate) {
        _signaling.sendToCamera(
          msg.cameraId,
          SignalingMessage(
            type: 'ice_candidate',
            cameraId: msg.cameraId,
            payload: {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          ),
        );
      },
      onRemoteStream: (stream) {
        if (_isDisposed) return;
        cameraNode.stream = stream;
        cameraNode.renderer.srcObject = stream;
        cameraNode.status = CameraConnectionState.connected;

        // Primera cámara -> EN VIVO; segunda cámara -> PREVIO (PVW)
        if (_activeLiveCameraId == null) {
          selectLiveCamera(cameraNode.id);
        } else {
          if (_activeLiveCameraId == cameraNode.id) {
            programRenderer.srcObject = stream;
          } else if (_previewCameraId == null) {
            selectPreviewCamera(cameraNode.id);
          } else if (_previewCameraId == cameraNode.id) {
            previewRenderer.srcObject = stream;
          }
          _syncAudioRouting();
        }
        _safeNotify();
      },
      onConnectionState: (state) {
        if (_isDisposed) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _removeCamera(msg.cameraId);
        }
      },
    );

    _signaling.sendToCamera(
      msg.cameraId,
      SignalingMessage(
        type: 'answer',
        cameraId: msg.cameraId,
        payload: {'sdp': answer.sdp, 'sdpType': answer.type},
      ),
    );
  }

  /// Acción al tocar una miniatura de cámara en la cuadrícula inferior
  Future<void> onSlotTapped(String cameraId) async {
    if (_studioMode) {
      selectPreviewCamera(cameraId);
    } else {
      await selectLiveCamera(cameraId);
    }
  }

  /// Carga una cámara en el monitor PREVIO (PVW) con Tally verde
  void selectPreviewCamera(String cameraId) {
    final node = _findNodeById(cameraId);
    if (node == null || node.stream == null) return;

    _previewCameraId = node.id;
    previewRenderer.srcObject = node.stream;
    _broadcastCurrentTally();
    _safeNotify();
  }

  /// Fase 3: Ejecuta TAKE pasando PVW a PGM e intercambiando la anterior PGM a PVW
  Future<void> takePreviewToLive() async {
    final nextLive = previewCamera;
    if (nextLive == null || nextLive.stream == null) return;
    final previousLiveId = _activeLiveCameraId;

    await selectLiveCamera(nextLive.id);

    if (previousLiveId != null && previousLiveId != nextLive.id) {
      final prevNode = _findNodeById(previousLiveId);
      if (prevNode != null && prevNode.stream != null) {
        _previewCameraId = prevNode.id;
        previewRenderer.srcObject = prevNode.stream;
        _broadcastCurrentTally();
        _safeNotify();
      }
    }
  }

  /// Alterna la cámara en el Monitor Principal EN VIVO (CUT o FADE)
  Future<void> selectLiveCamera(String cameraId) async {
    final node = _findNodeById(cameraId);
    if (node == null || node.stream == null) return;
    if (_activeLiveCameraId == node.id &&
        programRenderer.srcObject == node.stream) {
      return;
    }

    if (_transitionMode == TransitionMode.fade && _activeLiveCameraId != null) {
      _isFadingTransition = true;
      _safeNotify();
      await Future.delayed(const Duration(milliseconds: 160));
      if (_isDisposed) return;
    }

    _activeLiveCameraId = node.id;
    programRenderer.srcObject = node.stream;
    _syncAudioRouting();
    _broadcastCurrentTally();

    if (_recorder.isRecording && node.stream != null) {
      try {
        await _recorder.switchRecordedStream(node.stream!);
      } catch (e) {
        _lastError = 'Error al continuar grabación: $e';
      }
    }

    if (_isFadingTransition) {
      _safeNotify();
      await Future.delayed(const Duration(milliseconds: 50));
      if (_isDisposed) return;
      _isFadingTransition = false;
    }

    _safeNotify();
  }

  void _broadcastCurrentTally() {
    _signaling.broadcastTally(
      _activeLiveCameraId,
      previewCameraId: _studioMode ? _previewCameraId : null,
    );
  }

  void toggleStudioMode() {
    _studioMode = !_studioMode;
    if (_studioMode && _previewCameraId == null) {
      // Cargar en PVW alguna cámara distinta a la que está EN VIVO
      final candidate = slots.firstWhere(
        (s) => s != null && s.stream != null && s.id != _activeLiveCameraId,
        orElse: () => activeLiveCamera,
      );
      if (candidate != null && candidate.stream != null) {
        _previewCameraId = candidate.id;
        previewRenderer.srcObject = candidate.stream;
      }
    }
    _broadcastCurrentTally();
    _safeNotify();
  }

  void toggleTelemetry() {
    _showTelemetry = !_showTelemetry;
    _safeNotify();
  }

  /// Sincroniza el enrutamiento de audio (AFV: solo cámara EN VIVO o MIX manual)
  void _syncAudioRouting() {
    for (final slot in slots) {
      if (slot == null || slot.stream == null) continue;
      final shouldEnableAudio = isCameraAudioActive(slot);
      for (final track in slot.stream!.getAudioTracks()) {
        track.enabled = shouldEnableAudio;
      }
    }
  }

  void toggleAudioFollowsVideo() {
    _audioFollowsVideo = !_audioFollowsVideo;
    _syncAudioRouting();
    _safeNotify();
  }

  void toggleCameraMute(String cameraId) {
    final node = _findNodeById(cameraId);
    if (node == null) return;
    node.isAudioMuted = !node.isAudioMuted;
    _syncAudioRouting();
    _safeNotify();
  }

  void toggleTransitionMode() {
    _transitionMode = _transitionMode == TransitionMode.cut
        ? TransitionMode.fade
        : TransitionMode.cut;
    _safeNotify();
  }

  void updateOverlay(OverlayConfig config) {
    _overlayConfig = config;
    _safeNotify();
  }

  void remoteSwitchCamera(String cameraId) {
    _signaling.sendRemoteCommand(cameraId, 'switch_camera');
  }

  void remoteToggleTorch(String cameraId) {
    _signaling.sendRemoteCommand(cameraId, 'toggle_torch');
  }

  void remoteSetQuality(String cameraId, VideoQualityProfile profile) {
    _signaling.sendRemoteCommand(
      cameraId,
      'set_quality',
      params: {'quality': profile.id},
    );
  }

  /// Inicia o detiene la grabación local MP4 del Monitor Principal EN VIVO
  Future<List<String>?> toggleRecording() async {
    _lastError = null;

    if (_recorder.isRecording) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _recordingDuration = Duration.zero;
      final files = await _recorder.stopSession();
      _safeNotify();
      return files;
    }

    final liveStream = activeLiveCamera?.stream;
    if (liveStream == null) {
      _lastError = 'Conecta al menos una cámara EN VIVO antes de grabar.';
      _safeNotify();
      return null;
    }

    try {
      await _recorder.startSession(liveStream);
      _recordingDuration = Duration.zero;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isDisposed) return;
        _recordingDuration += const Duration(seconds: 1);
        _safeNotify();
      });
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudo iniciar la grabación: $e';
      _safeNotify();
    }
    return null;
  }

  Future<void> _removeCamera(String cameraId) async {
    final idx = slots.indexWhere((s) => s?.id == cameraId);
    if (idx == -1) return;

    final removed = slots[idx];
    slots[idx] = null;
    await _webrtc.removePeer(cameraId);
    await removed?.dispose();

    if (_previewCameraId == cameraId) {
      _previewCameraId = null;
      previewRenderer.srcObject = null;
    }

    if (_activeLiveCameraId == cameraId) {
      final fallback = slots.firstWhere(
        (s) => s != null && s.stream != null,
        orElse: () => null,
      );
      if (fallback != null) {
        await selectLiveCamera(fallback.id);
      } else {
        if (_recorder.isRecording) {
          await toggleRecording();
        }
        _activeLiveCameraId = null;
        programRenderer.srcObject = null;
        _broadcastCurrentTally();
      }
    } else {
      _broadcastCurrentTally();
    }
    _safeNotify();
  }

  CameraNode? _findNodeById(String? id) {
    if (id == null) return null;
    for (final slot in slots) {
      if (slot?.id == id) return slot;
    }
    return null;
  }

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _telemetryTimer?.cancel();
    _recordingTimer?.cancel();
    _recorder.dispose();
    WakelockPlus.disable();
    _discovery.dispose();
    _signaling.stop();
    _webrtc.dispose();
    for (final slot in slots) {
      slot?.dispose();
    }
    programRenderer.srcObject = null;
    programRenderer.dispose();
    previewRenderer.srcObject = null;
    previewRenderer.dispose();
    super.dispose();
  }
}
