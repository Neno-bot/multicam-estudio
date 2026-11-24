import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/network_constants.dart';
import '../../core/models/camera_node.dart';
import '../../core/models/media_overlay_config.dart';
import '../../core/models/overlay_config.dart';
import '../../core/models/signaling_message.dart';
import '../../core/models/video_quality_profile.dart';
import '../../services/discovery/local_discovery_service.dart';
import '../../services/recording/program_recorder_service.dart';
import '../../services/signaling/director_signaling_server.dart';
import '../../services/streaming/rtmp_stream_service.dart';
import '../../services/webrtc/director_webrtc_service.dart';

class DirectorController extends ChangeNotifier {
  final LocalDiscoveryService _discovery = LocalDiscoveryService();
  final DirectorSignalingServer _signaling = DirectorSignalingServer();
  final DirectorWebRTCService _webrtc = DirectorWebRTCService();
  final ProgramRecorderService _recorder = ProgramRecorderService();
  final RtmpStreamService _rtmpService = RtmpStreamService();
  final ImagePicker _imagePicker = ImagePicker();

  /// Renderer exclusivo del Monitor Principal EN VIVO (PGM)
  final RTCVideoRenderer programRenderer = RTCVideoRenderer();

  /// Renderer exclusivo del Monitor PREVIO (PVW) en Modo Estudio
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

  // Audio: SOLO TABLET por defecto (teléfonos emisores silenciados)
  AudioMixMode _audioMixMode = AudioMixMode.tabletOnly;
  TransitionMode _transitionMode = TransitionMode.cut;
  bool _isFadingTransition = false;
  OverlayConfig _overlayConfig = const OverlayConfig();

  // Imágenes y Videos en la transmisión
  ImageOverlayConfig _imageOverlay = const ImageOverlayConfig();
  VideoPlayerController? _localVideoController;
  bool _isPlayingLocalVideo = false;
  bool _isLocalVideoLooping = false;
  bool _isLocalVideoMuted = false;

  // Modo Estudio, Telemetría y Modo Pantalla Limpia (para YouTube/Facebook Live)
  bool _studioMode = false;
  bool _showTelemetry = true;
  bool _cleanBroadcastMode = false;
  Timer? _telemetryTimer;

  // Streaming RTMP / RTMPS (YouTube Live & Facebook Live)
  StreamSubscription<RtmpStreamEvent>? _rtmpSub;
  RtmpStreamStatus _rtmpStatus = RtmpStreamStatus.idle;
  String? _rtmpStatusMessage;
  String? _rtmpBitrateKbps;

  // Grabación local MP4
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  String? _lastError;

  String? get activeLiveCameraId => _activeLiveCameraId;
  String? get previewCameraId => _previewCameraId;
  String get localIp => _localIp;
  bool get isRunning => _isRunning;
  AudioMixMode get audioMixMode => _audioMixMode;
  TransitionMode get transitionMode => _transitionMode;
  bool get isFadingTransition => _isFadingTransition;
  OverlayConfig get overlayConfig => _overlayConfig;
  ImageOverlayConfig get imageOverlay => _imageOverlay;
  VideoPlayerController? get localVideoController => _localVideoController;
  bool get hasLocalVideo =>
      _localVideoController != null &&
      _localVideoController!.value.isInitialized;
  bool get isPlayingLocalVideo => _isPlayingLocalVideo && hasLocalVideo;
  bool get isVideoControllerPlaying =>
      _localVideoController?.value.isPlaying == true;
  bool get isLocalVideoLooping => _isLocalVideoLooping;
  bool get isLocalVideoMuted => _isLocalVideoMuted;
  bool get studioMode => _studioMode;
  bool get showTelemetry => _showTelemetry;
  bool get cleanBroadcastMode => _cleanBroadcastMode;
  RtmpStreamStatus get rtmpStatus => _rtmpStatus;
  bool get isRtmpLive =>
      _rtmpStatus == RtmpStreamStatus.live ||
      _rtmpStatus == RtmpStreamStatus.connecting;
  String? get rtmpStatusMessage => _rtmpStatusMessage;
  String? get rtmpBitrateKbps => _rtmpBitrateKbps;
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

  String get audioModeLabel {
    switch (_audioMixMode) {
      case AudioMixMode.tabletOnly:
        return 'SOLO TABLET';
      case AudioMixMode.afv:
        return 'AFV';
      case AudioMixMode.mix:
        return 'MIX';
    }
  }

  /// Indica si el audio remoto de un teléfono está activo en la Tablet
  bool isCameraAudioActive(CameraNode node) {
    if (_audioMixMode == AudioMixMode.tabletOnly) return false;
    if (node.isAudioMuted) return false;
    if (_audioMixMode == AudioMixMode.afv) return node.id == _activeLiveCameraId;
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

    _listenRtmpEvents();
    _startTelemetryPolling();
    _isRunning = true;
    _safeNotify();
  }

  void _listenRtmpEvents() {
    _rtmpSub?.cancel();
    _rtmpSub = _rtmpService.events.listen((evt) {
      if (_isDisposed) return;
      switch (evt.event) {
        case 'connecting':
          _rtmpStatus = RtmpStreamStatus.connecting;
          _rtmpStatusMessage = evt.message;
          break;
        case 'connected':
          _rtmpStatus = RtmpStreamStatus.live;
          _rtmpStatusMessage = 'EN VIVO (YouTube / Facebook)';
          break;
        case 'bitrate':
          _rtmpBitrateKbps = evt.message;
          break;
        case 'disconnected':
          _rtmpStatus = RtmpStreamStatus.idle;
          _rtmpStatusMessage = null;
          _rtmpBitrateKbps = null;
          break;
        case 'error':
          _rtmpStatus = RtmpStreamStatus.error;
          _rtmpStatusMessage = evt.message;
          _lastError = evt.message;
          break;
      }
      _safeNotify();
    });
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

  // ---- TRANSMISIÓN RTMP / RTMPS (YOUTUBE LIVE / FACEBOOK LIVE) ----

  Future<void> startRtmpLive({
    required String rtmpUrl,
    required int bitrateKbps,
    required bool enterCleanMode,
  }) async {
    _lastError = null;
    try {
      _rtmpStatus = RtmpStreamStatus.connecting;
      _rtmpStatusMessage = 'Solicitando permiso de transmisión...';
      if (enterCleanMode) {
        _cleanBroadcastMode = true;
      }
      _safeNotify();

      await _rtmpService.startStream(
        rtmpUrl: rtmpUrl,
        bitrateKbps: bitrateKbps,
        audioEnabled: true, // Usa el micrófono de la Tablet Director
      );
    } catch (e) {
      _rtmpStatus = RtmpStreamStatus.idle;
      _rtmpStatusMessage = null;
      _cleanBroadcastMode = false;
      _lastError = 'No se inició la transmisión: $e';
      _safeNotify();
    }
  }

  Future<void> stopRtmpLive() async {
    try {
      await _rtmpService.stopStream();
    } catch (_) {}
    _rtmpStatus = RtmpStreamStatus.idle;
    _rtmpStatusMessage = null;
    _rtmpBitrateKbps = null;
    _cleanBroadcastMode = false;
    _safeNotify();
  }

  void toggleCleanBroadcastMode() {
    _cleanBroadcastMode = !_cleanBroadcastMode;
    _safeNotify();
  }

  // ---- IMÁGENES EN LA TRANSMISIÓN (LOGO / PLACA PANTALLA COMPLETA) ----

  Future<void> pickOverlayImage() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null || _isDisposed) return;
      _imageOverlay = _imageOverlay.copyWith(
        filePath: picked.path,
        isVisible: true,
      );
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudo cargar la imagen: $e';
      _safeNotify();
    }
  }

  void setImageOverlayVisible(bool visible) {
    _imageOverlay = _imageOverlay.copyWith(isVisible: visible);
    _safeNotify();
  }

  void setImageOverlayPlacement(ImageOverlayPlacement placement) {
    _imageOverlay = _imageOverlay.copyWith(placement: placement);
    _safeNotify();
  }

  void setImageOverlaySize(double factor) {
    _imageOverlay = _imageOverlay.copyWith(sizeFactor: factor);
    _safeNotify();
  }

  void clearImageOverlay() {
    _imageOverlay = const ImageOverlayConfig();
    _safeNotify();
  }

  // ---- VIDEOS LOCALES (MP4 EN MONITOR EN VIVO) ----

  Future<void> pickAndPlayVideo() async {
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null || _isDisposed) return;

      await _disposeLocalVideo();
      final controller = VideoPlayerController.file(File(picked.path));
      await controller.initialize();
      if (_isDisposed) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(_isLocalVideoLooping);
      await controller.setVolume(_isLocalVideoMuted ? 0.0 : 1.0);
      await controller.play();

      _localVideoController = controller;
      _isPlayingLocalVideo = true;
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudo reproducir el video: $e';
      _safeNotify();
    }
  }

  Future<void> toggleLocalVideoPlayPause() async {
    final vc = _localVideoController;
    if (vc == null || !vc.value.isInitialized) return;
    if (vc.value.isPlaying) {
      await vc.pause();
    } else {
      _isPlayingLocalVideo = true;
      await vc.play();
    }
    _safeNotify();
  }

  Future<void> restartLocalVideo() async {
    final vc = _localVideoController;
    if (vc == null || !vc.value.isInitialized) return;
    await vc.seekTo(Duration.zero);
    _isPlayingLocalVideo = true;
    await vc.play();
    _safeNotify();
  }

  Future<void> toggleLocalVideoLoop() async {
    _isLocalVideoLooping = !_isLocalVideoLooping;
    await _localVideoController?.setLooping(_isLocalVideoLooping);
    _safeNotify();
  }

  Future<void> toggleLocalVideoMute() async {
    _isLocalVideoMuted = !_isLocalVideoMuted;
    await _localVideoController?.setVolume(_isLocalVideoMuted ? 0.0 : 1.0);
    _safeNotify();
  }

  Future<void> stopLocalVideoAndReturnToCameras() async {
    _isPlayingLocalVideo = false;
    await _localVideoController?.pause();
    _safeNotify();
  }

  Future<void> _disposeLocalVideo() async {
    _isPlayingLocalVideo = false;
    final old = _localVideoController;
    _localVideoController = null;
    await old?.dispose();
  }

  // ---- SEÑALIZACIÓN Y WEBRTC MULTICÁMARA ----

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
      isAudioMuted: true, // Silenciada por defecto
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

  Future<void> onSlotTapped(String cameraId) async {
    if (_studioMode) {
      selectPreviewCamera(cameraId);
    } else {
      await selectLiveCamera(cameraId);
    }
  }

  void selectPreviewCamera(String cameraId) {
    final node = _findNodeById(cameraId);
    if (node == null || node.stream == null) return;

    _previewCameraId = node.id;
    previewRenderer.srcObject = node.stream;
    _broadcastCurrentTally();
    _safeNotify();
  }

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

  Future<void> selectLiveCamera(String cameraId) async {
    final node = _findNodeById(cameraId);
    if (node == null || node.stream == null) return;

    // Al seleccionar una cámara en vivo, pausar video local si estaba al aire
    if (_isPlayingLocalVideo) {
      _isPlayingLocalVideo = false;
      await _localVideoController?.pause();
    }

    if (_activeLiveCameraId == node.id &&
        programRenderer.srcObject == node.stream) {
      _safeNotify();
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

  void _syncAudioRouting() {
    for (final slot in slots) {
      if (slot == null || slot.stream == null) continue;
      final shouldEnableAudio = isCameraAudioActive(slot);
      for (final track in slot.stream!.getAudioTracks()) {
        track.enabled = shouldEnableAudio;
      }
    }
  }

  /// Cicla el modo de audio: SOLO TABLET -> AFV -> MIX -> SOLO TABLET
  void cycleAudioMixMode() {
    switch (_audioMixMode) {
      case AudioMixMode.tabletOnly:
        _audioMixMode = AudioMixMode.afv;
        break;
      case AudioMixMode.afv:
        _audioMixMode = AudioMixMode.mix;
        break;
      case AudioMixMode.mix:
        _audioMixMode = AudioMixMode.tabletOnly;
        break;
    }
    _syncAudioRouting();
    _safeNotify();
  }

  void toggleCameraMute(String cameraId) {
    final node = _findNodeById(cameraId);
    if (node == null) return;
    node.isAudioMuted = !node.isAudioMuted;
    // Si el usuario activa manualmente una cámara mientras estaba en SOLO TABLET,
    // pasar a MIX para que se escuche esa cámara si así lo desea.
    if (!node.isAudioMuted && _audioMixMode == AudioMixMode.tabletOnly) {
      _audioMixMode = AudioMixMode.mix;
    }
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
    _rtmpSub?.cancel();
    if (isRtmpLive) {
      _rtmpService.stopStream();
    }
    _disposeLocalVideo();
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
