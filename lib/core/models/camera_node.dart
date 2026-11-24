import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'stream_stats.dart';
import 'video_quality_profile.dart';

enum CameraConnectionState {
  connecting,
  connected,
  disconnected,
}

class CameraNode {
  final String id;
  String name;
  final int slotIndex;
  final RTCVideoRenderer renderer;
  MediaStream? stream;
  CameraConnectionState status;
  bool isAudioMuted;
  bool isTorchOn;
  VideoQualityProfile quality;
  StreamStats? stats;

  CameraNode({
    required this.id,
    required this.name,
    required this.slotIndex,
    required this.renderer,
    this.stream,
    this.status = CameraConnectionState.connecting,
    this.isAudioMuted = false,
    this.isTorchOn = false,
    this.quality = VideoQualityProfile.hd720p,
    this.stats,
  });

  Future<void> dispose() async {
    renderer.srcObject = null;
    await renderer.dispose();
  }
}
