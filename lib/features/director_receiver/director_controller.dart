import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/network_constants.dart';
import '../../core/models/camera_node.dart';
import '../../core/models/media_cue_item.dart';
import '../../core/models/media_overlay_config.dart';
import '../../core/models/overlay_config.dart';
import '../../core/models/overlay_layer_item.dart';
import '../../core/models/signaling_message.dart';
import '../../core/models/video_quality_profile.dart';
import '../../services/discovery/local_discovery_service.dart';
import '../../services/recording/gallery_recorder_service.dart';
import '../../services/recording/program_recorder_service.dart';
import '../../services/signaling/director_signaling_server.dart';
import '../../services/streaming/rtmp_stream_service.dart';
import '../../services/webrtc/director_webrtc_service.dart';

enum DirectorSideTab { pauta, overlays }

class DirectorController extends ChangeNotifier {
  final LocalDiscoveryService _discovery = LocalDiscoveryService();
  final DirectorSignalingServer _signaling = DirectorSignalingServer();
  final DirectorWebRTCService _webrtc = DirectorWebRTCService();
  final ProgramRecorderService _recorder = ProgramRecorderService();
  final GalleryRecorderService _galleryRecorder = GalleryRecorderService();
  final RtmpStreamService _rtmpService = RtmpStreamService();
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();

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
  TransitionMode _transitionMode = TransitionMode.fade;
  bool _isFadingTransition = false;
  OverlayConfig _overlayConfig = const OverlayConfig();

  // v1.3-v1.4: Bandeja de Pauta Switcher (Múltiples imágenes + videos a la palma de la mano)
  final List<MediaCueItem> _mediaCues = [];
  String? _activeProgramCueId; // Placa pantalla completa o Video activo
  String? _activeLogoCueId; // Logo en esquina activo sobre cámaras
  bool _showPautaPanel = true;
  DirectorSideTab _sideTab = DirectorSideTab.pauta;
  int _imgCounter = 0;
  int _vidCounter = 0;

  // v1.5: Sistema independiente de Capas / Overlays (Downstream Keyer)
  // Totalmente separado de Pauta Media (+IMG/+VID), Cámaras (CAM 1-4) y Audio en vivo
  final List<OverlayLayerItem> _overlayLayers = [];
  final Map<String, VideoPlayerController> _overlayVideoControllers = {};
  WatermarkConfig _watermarkConfig = const WatermarkConfig();
  int _overlayCounter = 0;

  // Imágenes y Videos en la transmisión
  ImageOverlayConfig _imageOverlay = const ImageOverlayConfig();
  VideoPlayerController? _localVideoController;
  String? _loadedVideoPath;
  bool _isPlayingLocalVideo = false;
  bool _isLocalVideoLooping = true;
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

  // Grabación local MP4 (Galería Movies/NenoCam Studio)
  StreamSubscription<GalleryRecordEvent>? _galleryRecordSub;
  bool _isGalleryRecording = false;
  String? _lastSavedRecordingMessage;
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
  List<MediaCueItem> get mediaCues => List.unmodifiable(_mediaCues);
  List<MediaCueItem> get imageCues => _mediaCues
      .where((c) => c.type == MediaCueType.image)
      .toList(growable: false);
  List<MediaCueItem> get videoCues => _mediaCues
      .where((c) => c.type == MediaCueType.video)
      .toList(growable: false);
  bool get showPautaPanel => _showPautaPanel;
  DirectorSideTab get sideTab => _sideTab;
  List<OverlayLayerItem> get overlayLayers => List.unmodifiable(_overlayLayers);
  WatermarkConfig get watermarkConfig => _watermarkConfig;
  int get activeOverlayCount =>
      _overlayLayers.where((o) => o.isActive).length +
      (_watermarkConfig.isVisible && _watermarkConfig.hasImage ? 1 : 0);
  VideoPlayerController? overlayVideoControllerFor(String overlayId) =>
      _overlayVideoControllers[overlayId];
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
  bool get isRecording => _isGalleryRecording || _recorder.isRecording;
  Duration get recordingDuration => _recordingDuration;
  String? get lastSavedRecordingMessage => _lastSavedRecordingMessage;
  String? get lastError => _lastError;

  int get connectedCount => slots.where((s) => s != null).length;

  CameraNode? get activeLiveCamera => _findNodeById(_activeLiveCameraId);
  CameraNode? get previewCamera => _findNodeById(_previewCameraId);

  bool get canTake =>
      _studioMode &&
      previewCamera != null &&
      previewCamera!.stream != null &&
      previewCamera!.id != _activeLiveCameraId;

  bool isCueActive(String cueId) =>
      cueId == _activeProgramCueId || cueId == _activeLogoCueId;

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
    _listenGalleryRecordEvents();
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

  void _listenGalleryRecordEvents() {
    _galleryRecordSub?.cancel();
    _galleryRecordSub = _galleryRecorder.events.listen((evt) {
      if (_isDisposed) return;
      switch (evt.event) {
        case 'started':
          _isGalleryRecording = true;
          _recordingDuration = Duration.zero;
          _recordingTimer?.cancel();
          _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (_isDisposed) return;
            _recordingDuration += const Duration(seconds: 1);
            _safeNotify();
          });
          break;
        case 'saved':
          _isGalleryRecording = false;
          _recordingTimer?.cancel();
          _recordingTimer = null;
          _recordingDuration = Duration.zero;
          _cleanBroadcastMode = false;
          _lastSavedRecordingMessage = 'Video guardado en ${evt.message}';
          break;
        case 'error':
          _isGalleryRecording = false;
          _recordingTimer?.cancel();
          _recordingTimer = null;
          _recordingDuration = Duration.zero;
          _cleanBroadcastMode = false;
          _lastError = evt.message;
          break;
      }
      _safeNotify();
    });
  }

  String? consumeLastSavedRecordingMessage() {
    final msg = _lastSavedRecordingMessage;
    _lastSavedRecordingMessage = null;
    return msg;
  }

  String? consumeLastError() {
    final err = _lastError;
    _lastError = null;
    return err;
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

  // ---- HELPER TRANSICIÓN CUT / FADE (CÁMARAS, IMÁGENES Y VIDEOS) ----

  Future<void> _runWithTransition(Future<void> Function() applyChange) async {
    if (_transitionMode == TransitionMode.fade) {
      _isFadingTransition = true;
      _safeNotify();
      await Future.delayed(const Duration(milliseconds: 150));
      if (_isDisposed) return;
    }

    await applyChange();
    if (_isDisposed) return;

    if (_isFadingTransition) {
      _safeNotify();
      await Future.delayed(const Duration(milliseconds: 45));
      if (_isDisposed) return;
      _isFadingTransition = false;
    }
    _safeNotify();
  }

  // ---- v1.3: PAUTA MEDIA SWITCHER (MÚLTIPLES IMÁGENES Y VIDEOS EN 1 TOQUE) ----

  void togglePautaPanel() {
    _showPautaPanel = !_showPautaPanel;
    _safeNotify();
  }

  void setSideTab(DirectorSideTab tab) {
    _sideTab = tab;
    _showPautaPanel = true;
    _safeNotify();
  }

  void openOverlaysTab() {
    if (_showPautaPanel && _sideTab == DirectorSideTab.overlays) {
      _showPautaPanel = false;
    } else {
      _sideTab = DirectorSideTab.overlays;
      _showPautaPanel = true;
    }
    _safeNotify();
  }

  // ---- v1.5: CAPAS / OVERLAYS INDEPENDIENTES (DOWNSTREAM KEYER) ----
  // Activar/desactivar/cambiar aquí NUNCA detiene cámaras, pauta ni audio en vivo.

  Future<void> addOverlayTemplates() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'gif', 'webp', 'webm'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty || _isDisposed) return;

      for (final file in result.files) {
        final path = file.path;
        if (path == null || path.isEmpty) continue;
        _overlayCounter++;
        final format = OverlayMediaFormat.fromPath(path);
        final rawName = file.name.trim();
        final dotIdx = rawName.lastIndexOf('.');
        final cleanName = dotIdx > 0 ? rawName.substring(0, dotIdx) : rawName;

        _overlayLayers.add(
          OverlayLayerItem(
            id: _uuid.v4(),
            name: cleanName.isNotEmpty ? cleanName : 'Plantilla $_overlayCounter',
            filePath: path,
            format: format,
            isActive: false,
            opacity: 1.0,
            position: OverlayPosition.fullscreen,
          ),
        );
      }

      _sideTab = DirectorSideTab.overlays;
      _showPautaPanel = true;
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudo cargar la plantilla overlay: $e';
      _safeNotify();
    }
  }

  /// Interruptor individual ON/OFF con transición suave de opacidad (fade).
  /// Totalmente independiente de la cámara activa, pauta media y audio.
  Future<void> toggleOverlayLayer(String overlayId, bool active) async {
    final idx = _overlayLayers.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final item = _overlayLayers[idx];

    if (item.format.isVideo) {
      if (active) {
        try {
          var vc = _overlayVideoControllers[overlayId];
          if (vc == null) {
            vc = VideoPlayerController.file(File(item.filePath));
            await vc.initialize();
            if (_isDisposed) {
              await vc.dispose();
              return;
            }
            await vc.setLooping(true);
            await vc.setVolume(0.0); // No interrumpe el audio en vivo
            _overlayVideoControllers[overlayId] = vc;
          } else {
            await vc.seekTo(Duration.zero);
          }
          await vc.play();
        } catch (e) {
          _lastError = 'No se pudo reproducir overlay WebM: $e';
          _safeNotify();
          return;
        }
      } else {
        await _overlayVideoControllers[overlayId]?.pause();
      }
    }

    if (_isDisposed) return;
    final currentIdx = _overlayLayers.indexWhere((o) => o.id == overlayId);
    if (currentIdx == -1) return;
    _overlayLayers[currentIdx] =
        _overlayLayers[currentIdx].copyWith(isActive: active);
    _safeNotify();
  }

  void setOverlayOpacity(String overlayId, double opacity) {
    final idx = _overlayLayers.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    _overlayLayers[idx] =
        _overlayLayers[idx].copyWith(opacity: opacity.clamp(0.1, 1.0));
    _safeNotify();
  }

  void cycleOverlayPosition(String overlayId) {
    final idx = _overlayLayers.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final nextPos = switch (_overlayLayers[idx].position) {
      OverlayPosition.fullscreen => OverlayPosition.bottom,
      OverlayPosition.bottom => OverlayPosition.top,
      OverlayPosition.top => OverlayPosition.fullscreen,
    };
    _overlayLayers[idx] = _overlayLayers[idx].copyWith(position: nextPos);
    _safeNotify();
  }

  Future<void> removeOverlayLayer(String overlayId) async {
    _overlayLayers.removeWhere((o) => o.id == overlayId);
    final vc = _overlayVideoControllers.remove(overlayId);
    await vc?.dispose();
    _safeNotify();
  }

  // ---- SLOT FIJO: MARCA DE AGUA / LOGO (NIVEL SUPERIOR) ----

  Future<void> pickWatermarkImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'webp', 'gif'],
        allowMultiple: false,
      );
      final path = (result != null && result.files.isNotEmpty)
          ? result.files.first.path
          : null;
      if (path == null || path.isEmpty || _isDisposed) return;

      _watermarkConfig = _watermarkConfig.copyWith(
        filePath: path,
        isVisible: true,
      );
      _sideTab = DirectorSideTab.overlays;
      _showPautaPanel = true;
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudo cargar la marca de agua: $e';
      _safeNotify();
    }
  }

  void setWatermarkVisible(bool visible) {
    if (!_watermarkConfig.hasImage) return;
    _watermarkConfig = _watermarkConfig.copyWith(isVisible: visible);
    _safeNotify();
  }

  void setWatermarkOpacity(double opacity) {
    _watermarkConfig =
        _watermarkConfig.copyWith(opacity: opacity.clamp(0.15, 1.0));
    _safeNotify();
  }

  void setWatermarkScale(double scale) {
    _watermarkConfig = _watermarkConfig.copyWith(scale: scale.clamp(0.08, 0.35));
    _safeNotify();
  }

  void cycleWatermarkCorner() {
    final next = switch (_watermarkConfig.corner) {
      WatermarkCorner.topRight => WatermarkCorner.topLeft,
      WatermarkCorner.topLeft => WatermarkCorner.bottomLeft,
      WatermarkCorner.bottomLeft => WatermarkCorner.bottomRight,
      WatermarkCorner.bottomRight => WatermarkCorner.topRight,
    };
    _watermarkConfig = _watermarkConfig.copyWith(corner: next);
    _safeNotify();
  }

  void clearWatermark() {
    _watermarkConfig = const WatermarkConfig();
    _safeNotify();
  }

  /// Permite seleccionar varias imágenes a la vez (ej: 4 placas) y dejarlas pautadas
  Future<void> addImagesToPauta() async {
    try {
      final pickedList = await _imagePicker.pickMultiImage();
      if (pickedList.isEmpty || _isDisposed) return;

      for (final file in pickedList) {
        _imgCounter++;
        _mediaCues.add(
          MediaCueItem(
            id: _uuid.v4(),
            label: 'IMG $_imgCounter',
            filePath: file.path,
            type: MediaCueType.image,
            imagePlacement: ImageOverlayPlacement.fullscreenSlide,
          ),
        );
      }
      _showPautaPanel = true;
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudieron agregar imágenes: $e';
      _safeNotify();
    }
  }

  /// Añade un video local MP4 a la pauta (listo para lanzar en 1 toque)
  Future<void> addVideoToPauta() async {
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null || _isDisposed) return;

      _vidCounter++;
      _mediaCues.add(
        MediaCueItem(
          id: _uuid.v4(),
          label: 'VID $_vidCounter',
          filePath: picked.path,
          type: MediaCueType.video,
        ),
      );
      _showPautaPanel = true;
      _safeNotify();
    } catch (e) {
      _lastError = 'No se pudo agregar el video: $e';
      _safeNotify();
    }
  }

  /// Lanza al aire o quita un elemento de la Pauta con transición CUT / FADE
  Future<void> triggerMediaCue(String cueId) async {
    final idx = _mediaCues.indexWhere((c) => c.id == cueId);
    if (idx == -1) return;
    final cue = _mediaCues[idx];

    // 1. Si es Logo en esquina: alternar sin interrumpir video ni cámara
    if (cue.isCornerLogo) {
      if (_activeLogoCueId == cue.id) {
        _activeLogoCueId = null;
        if (_activeProgramCueId == null ||
            _findCueById(_activeProgramCueId)?.type != MediaCueType.image) {
          _imageOverlay = const ImageOverlayConfig();
        }
      } else {
        _activeLogoCueId = cue.id;
        _imageOverlay = ImageOverlayConfig(
          filePath: cue.filePath,
          isVisible: true,
          placement: cue.imagePlacement,
          sizeFactor: _imageOverlay.sizeFactor,
        );
      }
      _safeNotify();
      return;
    }

    // 2. Si ya estaba activo en pantalla completa -> apagarlo y volver a cámara con transición
    if (_activeProgramCueId == cue.id) {
      await _runWithTransition(() async {
        _activeProgramCueId = null;
        if (cue.type == MediaCueType.video) {
          _isPlayingLocalVideo = false;
          await _localVideoController?.pause();
        } else {
          _restoreLogoOrClearImage();
        }
      });
      return;
    }

    // 3. Activar nueva Placa (Imagen pantalla completa) o Video en vivo con transición
    if (cue.type == MediaCueType.image) {
      await _runWithTransition(() async {
        _activeProgramCueId = cue.id;
        _isPlayingLocalVideo = false;
        await _localVideoController?.pause();
        _imageOverlay = ImageOverlayConfig(
          filePath: cue.filePath,
          isVisible: true,
          placement: ImageOverlayPlacement.fullscreenSlide,
          sizeFactor: _imageOverlay.sizeFactor,
        );
      });
    } else {
      await _playVideoFromPathWithTransition(cue.filePath, cueId: cue.id);
    }
  }

  /// Cambia una imagen de la pauta entre PLACA completa -> LOGO Der. -> LOGO Izq.
  void cycleCueImagePlacement(String cueId) {
    final idx = _mediaCues.indexWhere((c) => c.id == cueId);
    if (idx == -1) return;
    final cue = _mediaCues[idx];
    if (cue.type != MediaCueType.image) return;

    final nextPlacement = switch (cue.imagePlacement) {
      ImageOverlayPlacement.fullscreenSlide =>
        ImageOverlayPlacement.topRightLogo,
      ImageOverlayPlacement.topRightLogo => ImageOverlayPlacement.topLeftLogo,
      ImageOverlayPlacement.topLeftLogo =>
        ImageOverlayPlacement.fullscreenSlide,
    };

    final updated = cue.copyWith(imagePlacement: nextPlacement);
    _mediaCues[idx] = updated;

    // Actualizar en vivo si ese cue estaba al aire
    if (_activeProgramCueId == cueId || _activeLogoCueId == cueId) {
      if (updated.isCornerLogo) {
        if (_activeProgramCueId == cueId) _activeProgramCueId = null;
        _activeLogoCueId = cueId;
      } else {
        if (_activeLogoCueId == cueId) _activeLogoCueId = null;
        _activeProgramCueId = cueId;
      }
      _imageOverlay = _imageOverlay.copyWith(
        filePath: updated.filePath,
        isVisible: true,
        placement: updated.imagePlacement,
      );
    }
    _safeNotify();
  }

  Future<void> removeMediaCue(String cueId) async {
    _mediaCues.removeWhere((c) => c.id == cueId);
    if (_activeProgramCueId == cueId) {
      _activeProgramCueId = null;
      _isPlayingLocalVideo = false;
      await _localVideoController?.pause();
      _restoreLogoOrClearImage();
    }
    if (_activeLogoCueId == cueId) {
      _activeLogoCueId = null;
      if (_activeProgramCueId == null) {
        _imageOverlay = const ImageOverlayConfig();
      }
    }
    _safeNotify();
  }

  void _restoreLogoOrClearImage() {
    final logoCue = _findCueById(_activeLogoCueId);
    if (logoCue != null) {
      _imageOverlay = ImageOverlayConfig(
        filePath: logoCue.filePath,
        isVisible: true,
        placement: logoCue.imagePlacement,
        sizeFactor: _imageOverlay.sizeFactor,
      );
    } else {
      _imageOverlay = const ImageOverlayConfig();
    }
  }

  MediaCueItem? _findCueById(String? id) {
    if (id == null) return null;
    for (final c in _mediaCues) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _playVideoFromPathWithTransition(
    String path, {
    String? cueId,
  }) async {
    try {
      if (_loadedVideoPath != path || _localVideoController == null) {
        await _disposeLocalVideo();
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        if (_isDisposed) {
          await controller.dispose();
          return;
        }
        await controller.setLooping(_isLocalVideoLooping);
        await controller.setVolume(_isLocalVideoMuted ? 0.0 : 1.0);
        _localVideoController = controller;
        _loadedVideoPath = path;
      } else {
        await _localVideoController!.setLooping(_isLocalVideoLooping);
        await _localVideoController!.seekTo(Duration.zero);
      }

      await _runWithTransition(() async {
        _activeProgramCueId = cueId;
        _restoreLogoOrClearImage();
        _isPlayingLocalVideo = true;
        await _localVideoController!.play();
      });
    } catch (e) {
      _lastError = 'No se pudo reproducir el video: $e';
      _safeNotify();
    }
  }

  // ---- TRANSMISIÓN RTMP / RTMPS (YOUTUBE LIVE / FACEBOOK LIVE) ----

  Future<void> startRtmpLive({
    required String rtmpUrl,
    required int bitrateKbps,
    required bool enterCleanMode,
  }) async {
    _lastError = null;
    if (_isGalleryRecording) {
      _lastError = 'Detén primero la grabación en Galería antes de transmitir en vivo.';
      _safeNotify();
      return;
    }
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

  // ---- COMPATIBILIDAD DIÁLOGO MEDIA (IMAGEN ÚNICA / VIDEO ÚNICO) ----

  Future<void> pickOverlayImage() async {
    await addImagesToPauta();
    if (_mediaCues.isNotEmpty) {
      await triggerMediaCue(_mediaCues.last.id);
    }
  }

  void setImageOverlayVisible(bool visible) {
    _imageOverlay = _imageOverlay.copyWith(isVisible: visible);
    if (!visible) {
      _activeLogoCueId = null;
      if (_findCueById(_activeProgramCueId)?.type == MediaCueType.image) {
        _activeProgramCueId = null;
      }
    }
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
    _activeLogoCueId = null;
    if (_findCueById(_activeProgramCueId)?.type == MediaCueType.image) {
      _activeProgramCueId = null;
    }
    _imageOverlay = const ImageOverlayConfig();
    _safeNotify();
  }

  Future<void> pickAndPlayVideo() async {
    await addVideoToPauta();
    if (_mediaCues.isNotEmpty && _mediaCues.last.type == MediaCueType.video) {
      await triggerMediaCue(_mediaCues.last.id);
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
    await _runWithTransition(() async {
      _isPlayingLocalVideo = false;
      if (_findCueById(_activeProgramCueId)?.type == MediaCueType.video) {
        _activeProgramCueId = null;
      }
      await _localVideoController?.pause();
    });
  }

  Future<void> _disposeLocalVideo() async {
    _isPlayingLocalVideo = false;
    _loadedVideoPath = null;
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
      isAudioMuted: true,
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

  /// Selecciona una cámara al Monitor EN VIVO (quita placas/videos con transición suave)
  Future<void> selectLiveCamera(String cameraId) async {
    final node = _findNodeById(cameraId);
    if (node == null || node.stream == null) return;

    final switchingFromMedia =
        _activeProgramCueId != null || _isPlayingLocalVideo;

    if (!switchingFromMedia &&
        _activeLiveCameraId == node.id &&
        programRenderer.srcObject == node.stream) {
      return;
    }

    await _runWithTransition(() async {
      _activeProgramCueId = null;
      if (_isPlayingLocalVideo) {
        _isPlayingLocalVideo = false;
        await _localVideoController?.pause();
      }
      _restoreLogoOrClearImage();

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
    });
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

  /// Inicia la grabación completa de la producción directamente a la Galería (Movies/NenoCam Studio)
  Future<void> startGalleryRecording({
    int width = 1280,
    int height = 720,
    int bitrateKbps = 4000,
    bool audioEnabled = true,
    bool enterCleanMode = true,
  }) async {
    _lastError = null;
    if (isRtmpLive) {
      _lastError = 'Detén primero la transmisión EN VIVO antes de grabar a Galería.';
      _safeNotify();
      return;
    }
    try {
      if (enterCleanMode) {
        _cleanBroadcastMode = true;
        _safeNotify();
      }
      await _galleryRecorder.startRecording(
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        audioEnabled: audioEnabled,
      );
    } catch (e) {
      _isGalleryRecording = false;
      _cleanBroadcastMode = false;
      _lastError = 'No se inició la grabación: $e';
      _safeNotify();
    }
  }

  /// Detiene la grabación activa y publica el MP4 en la Galería del dispositivo
  Future<void> stopGalleryRecording() async {
    if (_isGalleryRecording) {
      try {
        await _galleryRecorder.stopRecording();
      } catch (e) {
        _isGalleryRecording = false;
        _recordingTimer?.cancel();
        _recordingTimer = null;
        _cleanBroadcastMode = false;
        _lastError = 'Error al detener la grabación: $e';
        _safeNotify();
      }
      return;
    }

    if (_recorder.isRecording) {
      await toggleRecording();
    }
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
    _galleryRecordSub?.cancel();
    if (isRtmpLive) {
      _rtmpService.stopStream();
    }
    if (_isGalleryRecording) {
      _galleryRecorder.stopRecording();
    }
    _disposeLocalVideo();
    for (final vc in _overlayVideoControllers.values) {
      vc.dispose();
    }
    _overlayVideoControllers.clear();
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
