import 'package:flutter_test/flutter_test.dart';
import 'package:multicam_studio/core/models/overlay_config.dart';
import 'package:multicam_studio/core/models/signaling_message.dart';
import 'package:multicam_studio/core/models/stream_stats.dart';
import 'package:multicam_studio/core/models/video_quality_profile.dart';

void main() {
  group('SignalingMessage', () {
    test('serializa y deserializa correctamente mensajes JSON', () {
      const original = SignalingMessage(
        type: 'command',
        cameraId: 'cam-01',
        payload: {'action': 'set_quality', 'quality': '1080p'},
      );

      final decoded = SignalingMessage.fromJsonString(original.toJsonString());
      expect(decoded.type, 'command');
      expect(decoded.cameraId, 'cam-01');
      expect(decoded.payload['action'], 'set_quality');
      expect(decoded.payload['quality'], '1080p');
    });
  });

  group('VideoQualityProfile', () {
    test('resuelve perfiles conocidos y aplica fallback 720p', () {
      expect(VideoQualityProfile.fromId('480p'), VideoQualityProfile.sd480p);
      expect(VideoQualityProfile.fromId('1080p'), VideoQualityProfile.fhd1080p);
      expect(
        VideoQualityProfile.fromId('unknown'),
        VideoQualityProfile.hd720p,
      );
      expect(VideoQualityProfile.fromId(null), VideoQualityProfile.hd720p);
    });
  });

  group('StreamStats', () {
    test('calcula salud de señal y formato legible', () {
      const goodStats = StreamStats(
        width: 1280,
        height: 720,
        fps: 30,
        bitrateKbps: 2450,
        rttMs: 14,
      );
      expect(goodStats.health, SignalHealth.good);
      expect(goodStats.bitrateLabel, '2.5 Mbps');
      expect(goodStats.compactSummary, '720p • 30fps • 2.5 Mbps • 14ms');

      const poorStats = StreamStats(
        width: 1280,
        height: 720,
        fps: 10,
        bitrateKbps: 420,
        rttMs: 240,
      );
      expect(poorStats.health, SignalHealth.poor);
      expect(poorStats.bitrateLabel, '420 kbps');
    });
  });

  group('OverlayConfig', () {
    test('copyWith conserva campos no modificados', () {
      const base = OverlayConfig(
        isVisible: false,
        title: 'Conferencia',
        subtitle: 'Sala A',
      );
      final live = base.copyWith(isVisible: true);
      expect(live.isVisible, true);
      expect(live.title, 'Conferencia');
      expect(live.subtitle, 'Sala A');
    });
  });
}
