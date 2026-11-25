import 'package:flutter_test/flutter_test.dart';
import 'package:multicam_studio/core/models/media_cue_item.dart';
import 'package:multicam_studio/core/models/media_overlay_config.dart';
import 'package:multicam_studio/core/models/overlay_config.dart';
import 'package:multicam_studio/core/models/overlay_layer_item.dart';
import 'package:multicam_studio/core/models/signaling_message.dart';
import 'package:multicam_studio/core/models/stream_stats.dart';
import 'package:multicam_studio/core/models/video_quality_profile.dart';
import 'package:multicam_studio/services/update/update_check_service.dart';

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

  group('UpdateCheckService', () {
    test('detecta versiones más nuevas correctamente', () {
      expect(
        UpdateCheckService.extractVersion('NenoCam Studio v1.3 (Nueva)'),
        '1.3',
      );
      expect(UpdateCheckService.isVersionNewer('1.3', '1.2.0'), true);
      expect(UpdateCheckService.isVersionNewer('1.2.0', '1.2.0'), false);
      expect(UpdateCheckService.isVersionNewer('1.1.9', '1.2.0'), false);
    });

    test('prioriza NenoCam-Studio-arm64.apk sobre archivos heredados', () {
      final url = UpdateCheckService.selectBestArm64AssetUrl([
        {
          'name': 'MultiCam-Studio-arm64.apk',
          'browser_download_url': 'https://example.com/old-arm64.apk',
        },
        {
          'name': 'NenoCam-Studio-arm64.apk',
          'browser_download_url': 'https://example.com/nenocam-arm64.apk',
        },
      ]);
      expect(url, 'https://example.com/nenocam-arm64.apk');
    });
  });

  group('MediaCueItem', () {
    test('distingue placa pantalla completa vs logo en esquina', () {
      const slide = MediaCueItem(
        id: '1',
        label: 'IMG 1',
        filePath: '/tmp/a.png',
        type: MediaCueType.image,
      );
      expect(slide.isCornerLogo, false);

      final logo = slide.copyWith(
        imagePlacement: ImageOverlayPlacement.topRightLogo,
      );
      expect(logo.isCornerLogo, true);
    });
  });

  group('OverlayLayerItem & WatermarkConfig', () {
    test('detecta formatos con transparencia y conserva propiedades en copyWith', () {
      expect(OverlayMediaFormat.fromPath('/tmp/cintillo.png'),
          OverlayMediaFormat.png);
      expect(OverlayMediaFormat.fromPath('/tmp/animado.GIF'),
          OverlayMediaFormat.gif);
      expect(OverlayMediaFormat.fromPath('/tmp/banner.webp'),
          OverlayMediaFormat.webp);
      expect(OverlayMediaFormat.fromPath('/tmp/alerta.webm'),
          OverlayMediaFormat.webm);
      expect(OverlayMediaFormat.webm.isVideo, true);

      const item = OverlayLayerItem(
        id: 'ov-1',
        name: 'Cintillo Alerta',
        filePath: '/tmp/cintillo.png',
        format: OverlayMediaFormat.png,
      );
      final live = item.copyWith(isActive: true, opacity: 0.85);
      expect(live.isActive, true);
      expect(live.opacity, 0.85);
      expect(live.name, 'Cintillo Alerta');

      const wm = WatermarkConfig(filePath: '/tmp/logo.png', isVisible: true);
      expect(wm.hasImage, true);
      expect(wm.corner, WatermarkCorner.topRight);
      expect(wm.copyWith(clearFile: true).hasImage, false);
    });
  });
}
