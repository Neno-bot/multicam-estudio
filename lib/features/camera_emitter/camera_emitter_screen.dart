import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../core/constants/network_constants.dart';
import '../../core/models/video_quality_profile.dart';
import 'camera_emitter_controller.dart';
import 'widgets/manual_connect_dialog.dart';

class CameraEmitterScreen extends StatelessWidget {
  const CameraEmitterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CameraEmitterController()..initialize(),
      child: const _CameraEmitterView(),
    );
  }
}

class _CameraEmitterView extends StatelessWidget {
  const _CameraEmitterView();

  Color _tallyColor(EmitterStatus status) {
    switch (status) {
      case EmitterStatus.streamingLive:
        return const Color(0xFFEF4444); // Rojo Tally EN VIVO (PGM)
      case EmitterStatus.streamingPreview:
        return const Color(0xFF22C55E); // Verde Tally PREVIO (PVW)
      case EmitterStatus.streamingStandby:
        return const Color(0xFF3B82F6); // Azul conectado en Standby
      case EmitterStatus.connecting:
        return const Color(0xFFF59E0B);
      case EmitterStatus.error:
        return Colors.deepOrange;
      default:
        return Colors.white24;
    }
  }

  Future<void> _openManualConnect(
    BuildContext context,
    CameraEmitterController ctrl,
  ) async {
    final result = await showDialog<ManualConnectResult>(
      context: context,
      builder: (_) => ManualConnectDialog(
        initialCameraName: ctrl.cameraName,
        initialHost: ctrl.connectedDirector?.host,
        initialPort:
            ctrl.connectedDirector?.port ?? NetworkConstants.signalingPort,
      ),
    );
    if (result == null) return;
    await ctrl.connectManually(
      host: result.host,
      port: result.port,
      newCameraName: result.cameraName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CameraEmitterController>();
    final borderColor = _tallyColor(ctrl.status);
    final showTallyFrame = ctrl.isLiveOnAir || ctrl.isPreviewReady;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Vista previa de cámara local a pantalla completa
          RTCVideoView(
            ctrl.localRenderer,
            mirror: ctrl.isFrontCamera,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),

          // Borde Tally dual (Rojo = EN VIVO / Verde = PREVIO PVW)
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                border: Border.all(
                  color: showTallyFrame ? borderColor : Colors.transparent,
                  width: showTallyFrame ? 8 : 0,
                ),
              ),
            ),
          ),

          // Barra superior de estado + botón QR/IP manual
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(185),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: borderColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                ctrl.isLiveOnAir
                                    ? 'EN VIVO • ${ctrl.cameraName}'
                                    : ctrl.isPreviewReady
                                        ? 'PREVIO (PVW) • ${ctrl.cameraName}'
                                        : '${ctrl.cameraName} • ${ctrl.statusDetail ?? ""}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      tooltip: 'Conexión manual IP / QR y nombre',
                      onPressed: () => _openManualConnect(context, ctrl),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Selector rápido de calidad (480p / 720p / 1080p) y controles inferiores
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Selector de resolución/bitrate en vivo
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(175),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: VideoQualityProfile.values.map((profile) {
                          final selected = ctrl.qualityProfile == profile;
                          return GestureDetector(
                            onTap: () => ctrl.setVideoQuality(profile),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF3B82F6)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                profile.label,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FloatingActionButton(
                          heroTag: 'mute_btn',
                          backgroundColor: ctrl.isMuted
                              ? Colors.redAccent
                              : Colors.black54,
                          onPressed: ctrl.toggleMute,
                          child: Icon(
                            ctrl.isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                          ),
                        ),
                        const SizedBox(width: 20),
                        FloatingActionButton(
                          heroTag: 'flip_btn',
                          backgroundColor: Colors.black54,
                          onPressed: ctrl.switchCamera,
                          child: const Icon(Icons.cameraswitch_rounded),
                        ),
                        const SizedBox(width: 20),
                        FloatingActionButton(
                          heroTag: 'torch_btn',
                          backgroundColor: ctrl.isTorchOn
                              ? Colors.amber.shade700
                              : Colors.black54,
                          onPressed:
                              ctrl.isFrontCamera ? null : ctrl.toggleTorch,
                          child: Icon(
                            ctrl.isTorchOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
