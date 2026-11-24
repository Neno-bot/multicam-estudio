import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/models/video_quality_profile.dart';

class CameraWebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isFrontCamera = false;
  bool _isMuted = true; // Teléfonos silenciados por defecto (Solo Tablet usa audio)
  bool _isTorchOn = false;
  bool _remoteDescriptionSet = false;
  VideoQualityProfile _qualityProfile = VideoQualityProfile.hd720p;
  final List<RTCIceCandidate> _pendingCandidates = [];

  MediaStream? get localStream => _localStream;
  bool get isFrontCamera => _isFrontCamera;
  bool get isMuted => _isMuted;
  bool get isTorchOn => _isTorchOn;
  VideoQualityProfile get qualityProfile => _qualityProfile;

  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [], // Red Wi-Fi local directa (host candidates = mínima latencia)
    'sdpSemantics': 'unified-plan',
  };

  Map<String, dynamic> _buildVideoConstraints(VideoQualityProfile profile) {
    return <String, dynamic>{
      'facingMode': _isFrontCamera ? 'user' : 'environment',
      'width': {'ideal': profile.width},
      'height': {'ideal': profile.height},
      'frameRate': {'ideal': profile.frameRate},
    };
  }

  /// Inicializa cámara y micrófono (silenciado por defecto para evitar eco con la Tablet)
  Future<MediaStream> initLocalMedia({
    VideoQualityProfile profile = VideoQualityProfile.hd720p,
  }) async {
    _qualityProfile = profile;
    final constraints = <String, dynamic>{
      'audio': true,
      'video': _buildVideoConstraints(profile),
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    return _localStream!;
  }

  /// Crea PeerConnection y genera la Oferta SDP para enviar al Director
  Future<RTCSessionDescription> createOffer({
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    required void Function(RTCPeerConnectionState state) onConnectionState,
  }) async {
    await closePeerConnection();

    _peerConnection = await createPeerConnection(_rtcConfig);
    _peerConnection!.onIceCandidate = onIceCandidate;
    _peerConnection!.onConnectionState = onConnectionState;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
      await _applyMaxBitrate(_qualityProfile.maxBitrateKbps);
    }

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<void> setRemoteAnswer(String sdp, String type) async {
    if (_peerConnection == null) return;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
    _remoteDescriptionSet = true;

    for (final candidate in _pendingCandidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> addIceCandidate(Map<String, dynamic> data) async {
    final candidate = RTCIceCandidate(
      data['candidate'] as String?,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    if (!_remoteDescriptionSet || _peerConnection == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _peerConnection!.addCandidate(candidate);
  }

  /// Fase 3: Cambia resolución y bitrate en caliente sin cortar la sesión WebRTC
  Future<MediaStream?> changeVideoQuality(VideoQualityProfile profile) async {
    if (profile == _qualityProfile && _localStream != null) {
      return _localStream;
    }
    _qualityProfile = profile;

    if (_isTorchOn) {
      await setTorch(false);
    }

    final newStream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': _buildVideoConstraints(profile),
    });

    final newVideoTrack = newStream.getVideoTracks().first;
    final oldVideoTracks = _localStream?.getVideoTracks() ?? [];

    // Reemplazar pista de video en el RTCPeerConnection activo sin renegociar
    if (_peerConnection != null) {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(newVideoTrack);
        }
      }
      await _applyMaxBitrate(profile.maxBitrateKbps);
    }

    // Actualizar stream local conservando la pista de audio existente
    if (_localStream != null) {
      for (final oldTrack in oldVideoTracks) {
        await _localStream!.removeTrack(oldTrack);
        oldTrack.stop();
      }
      await _localStream!.addTrack(newVideoTrack);
    } else {
      _localStream = newStream;
    }

    return _localStream;
  }

  Future<void> _applyMaxBitrate(int maxBitrateKbps) async {
    if (_peerConnection == null) return;
    try {
      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final params = sender.parameters;
          if (params.encodings != null && params.encodings!.isNotEmpty) {
            params.encodings!.first.maxBitrate = maxBitrateKbps * 1000;
            await sender.setParameters(params);
          }
        }
      }
    } catch (_) {}
  }

  /// Cambia entre cámara trasera y frontal sin cortar el stream WebRTC
  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      if (_isTorchOn) {
        await setTorch(false);
      }
      await Helper.switchCamera(videoTracks.first);
      _isFrontCamera = !_isFrontCamera;
    }
  }

  /// Enciende o apaga la linterna (disponible en cámara trasera)
  Future<bool> setTorch(bool enabled) async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks == null || videoTracks.isEmpty || _isFrontCamera) {
      _isTorchOn = false;
      return false;
    }
    try {
      final track = videoTracks.first;
      if (await track.hasTorch()) {
        await track.setTorch(enabled);
        _isTorchOn = enabled;
        return _isTorchOn;
      }
    } catch (_) {}
    _isTorchOn = false;
    return false;
  }

  Future<bool> toggleTorch() => setTorch(!_isTorchOn);

  void toggleMute() {
    _isMuted = !_isMuted;
    final audioTracks = _localStream?.getAudioTracks();
    if (audioTracks != null) {
      for (final track in audioTracks) {
        track.enabled = !_isMuted;
      }
    }
  }

  Future<void> closePeerConnection() async {
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    await _peerConnection?.close();
    _peerConnection = null;
  }

  Future<void> dispose() async {
    await closePeerConnection();
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
  }
}
