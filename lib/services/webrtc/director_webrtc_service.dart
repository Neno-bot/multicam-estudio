import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/models/stream_stats.dart';

class _BitrateSample {
  final int bytesReceived;
  final double timestampMs;

  const _BitrateSample(this.bytesReceived, this.timestampMs);
}

class DirectorWebRTCService {
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, bool> _remoteDescReady = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Map<String, _BitrateSample> _lastBitrateSample = {};

  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': [],
    'sdpSemantics': 'unified-plan',
  };

  /// Recibe Oferta de una cámara, prepara el stream remoto y devuelve la Respuesta SDP
  Future<RTCSessionDescription> handleCameraOffer({
    required String cameraId,
    required String sdp,
    required String sdpType,
    required void Function(RTCIceCandidate candidate) onIceCandidate,
    required void Function(MediaStream stream) onRemoteStream,
    required void Function(RTCPeerConnectionState state) onConnectionState,
  }) async {
    await removePeer(cameraId);

    final pc = await createPeerConnection(_rtcConfig);
    _peers[cameraId] = pc;
    _remoteDescReady[cameraId] = false;

    pc.onIceCandidate = onIceCandidate;
    pc.onConnectionState = onConnectionState;
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream(event.streams.first);
      }
    };

    await pc.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
    _remoteDescReady[cameraId] = true;

    final queued = _pendingCandidates.remove(cameraId);
    if (queued != null) {
      for (final candidate in queued) {
        await pc.addCandidate(candidate);
      }
    }

    final answer = await pc.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await pc.setLocalDescription(answer);
    return answer;
  }

  Future<void> addIceCandidate(
    String cameraId,
    Map<String, dynamic> data,
  ) async {
    final candidate = RTCIceCandidate(
      data['candidate'] as String?,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );

    final pc = _peers[cameraId];
    if (pc == null || _remoteDescReady[cameraId] != true) {
      _pendingCandidates.putIfAbsent(cameraId, () => []).add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  /// Fase 3: Extrae telemetría real (resolución, FPS, bitrate kbps, RTT ms y paquetes perdidos)
  Future<StreamStats?> getCameraStats(String cameraId) async {
    final pc = _peers[cameraId];
    if (pc == null) return null;

    try {
      final reports = await pc.getStats();
      int width = 0;
      int height = 0;
      double fps = 0;
      double bitrateKbps = 0;
      double rttMs = 0;
      int packetsLost = 0;

      for (final report in reports) {
        final values = report.values;
        if (report.type == 'inbound-rtp' &&
            (values['kind'] == 'video' || values['mediaType'] == 'video')) {
          width = _asInt(values['frameWidth']);
          height = _asInt(values['frameHeight']);
          fps = _asDouble(values['framesPerSecond']);
          packetsLost = _asInt(values['packetsLost']);

          final bytes = _asInt(values['bytesReceived']);
          final nowMs = report.timestamp > 0
              ? report.timestamp
              : DateTime.now().millisecondsSinceEpoch.toDouble();

          final prev = _lastBitrateSample[cameraId];
          if (prev != null && nowMs > prev.timestampMs && bytes >= prev.bytesReceived) {
            final deltaBytes = bytes - prev.bytesReceived;
            final deltaSec = (nowMs - prev.timestampMs) / 1000.0;
            if (deltaSec > 0) {
              bitrateKbps = (deltaBytes * 8) / (deltaSec * 1000.0);
            }
          }
          _lastBitrateSample[cameraId] = _BitrateSample(bytes, nowMs);
        } else if (report.type == 'candidate-pair' &&
            (values['state'] == 'succeeded' || values['nominated'] == true)) {
          final rttSec = _asDouble(values['currentRoundTripTime']);
          if (rttSec > 0) {
            rttMs = rttSec * 1000.0;
          }
        }
      }

      return StreamStats(
        width: width,
        height: height,
        fps: fps,
        bitrateKbps: bitrateKbps,
        rttMs: rttMs,
        packetsLost: packetsLost,
      );
    } catch (_) {
      return null;
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> removePeer(String cameraId) async {
    _remoteDescReady.remove(cameraId);
    _pendingCandidates.remove(cameraId);
    _lastBitrateSample.remove(cameraId);
    final pc = _peers.remove(cameraId);
    await pc?.close();
  }

  Future<void> dispose() async {
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _remoteDescReady.clear();
    _pendingCandidates.clear();
    _lastBitrateSample.clear();
  }
}
