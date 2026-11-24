import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/network_constants.dart';
import '../../core/models/overlay_config.dart';
import '../../core/utils/device_utils.dart';
import 'director_controller.dart';
import 'widgets/camera_slot_tile.dart';
import 'widgets/director_qr_dialog.dart';
import 'widgets/live_program_monitor.dart';
import 'widgets/lower_third_dialog.dart';
import 'widgets/preview_monitor.dart';

class DirectorScreen extends StatefulWidget {
  const DirectorScreen({super.key});

  @override
  State<DirectorScreen> createState() => _DirectorScreenState();
}

class _DirectorScreenState extends State<DirectorScreen> {
  @override
  void initState() {
    super.initState();
    DeviceUtils.lockLandscape();
  }

  @override
  void dispose() {
    DeviceUtils.unlockOrientations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DirectorController()..initialize(),
      child: const _DirectorView(),
    );
  }
}

class _DirectorView extends StatelessWidget {
  const _DirectorView();

  void _showQrDialog(BuildContext context, DirectorController ctrl) {
    showDialog<void>(
      context: context,
      builder: (_) => DirectorQrDialog(
        hostIp: ctrl.localIp,
        port: NetworkConstants.signalingPort,
      ),
    );
  }

  Future<void> _showLowerThirdDialog(
    BuildContext context,
    DirectorController ctrl,
  ) async {
    final result = await showDialog<OverlayConfig>(
      context: context,
      builder: (_) => LowerThirdDialog(initialConfig: ctrl.overlayConfig),
    );
    if (result != null) {
      ctrl.updateOverlay(result);
    }
  }

  Future<void> _handleToggleRecording(
    BuildContext context,
    DirectorController ctrl,
  ) async {
    final savedFiles = await ctrl.toggleRecording();
    if (!context.mounted) return;

    if (ctrl.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.lastError!)),
      );
      return;
    }

    if (savedFiles != null && savedFiles.isNotEmpty) {
      final count = savedFiles.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            count == 1
                ? 'Grabación guardada: ${savedFiles.first}'
                : 'Grabación guardada ($count clips): ${savedFiles.last}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();

    final programMonitor = LiveProgramMonitor(
      programRenderer: ctrl.programRenderer,
      activeCamera: ctrl.activeLiveCamera,
      isFadingTransition: ctrl.isFadingTransition,
      overlayConfig: ctrl.overlayConfig,
      isRecording: ctrl.isRecording,
      recordingDuration: ctrl.recordingDuration,
      showTelemetry: ctrl.showTelemetry,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Cabecera de control profesional del Director
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Salir del Modo Director',
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'DIRECTOR STUDIO',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Barra de controles Fases 2 y 3
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          children: [
                            _ActionChip(
                              icon: Icons.qr_code_2_rounded,
                              label: 'QR • ${ctrl.localIp}',
                              color: const Color(0xFF3B82F6),
                              onTap: () => _showQrDialog(context, ctrl),
                            ),
                            const SizedBox(width: 8),
                            _ActionChip(
                              icon: ctrl.studioMode
                                  ? Icons.view_column_rounded
                                  : Icons.crop_landscape_rounded,
                              label: ctrl.studioMode
                                  ? 'ESTUDIO (PVW/PGM)'
                                  : 'DIRECTO',
                              color: const Color(0xFF14B8A6),
                              highlighted: ctrl.studioMode,
                              onTap: ctrl.toggleStudioMode,
                            ),
                            const SizedBox(width: 8),
                            _ActionChip(
                              icon: Icons.speed_rounded,
                              label: 'STATS',
                              color: const Color(0xFF60A5FA),
                              highlighted: ctrl.showTelemetry,
                              onTap: ctrl.toggleTelemetry,
                            ),
                            const SizedBox(width: 8),
                            _ActionChip(
                              icon: ctrl.audioFollowsVideo
                                  ? Icons.hearing_rounded
                                  : Icons.graphic_eq_rounded,
                              label: ctrl.audioFollowsVideo
                                  ? 'AUDIO: AFV'
                                  : 'AUDIO: MIX',
                              color: ctrl.audioFollowsVideo
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFF59E0B),
                              onTap: ctrl.toggleAudioFollowsVideo,
                            ),
                            const SizedBox(width: 8),
                            _ActionChip(
                              icon: Icons.auto_awesome_motion_rounded,
                              label: ctrl.transitionMode == TransitionMode.cut
                                  ? 'CUT'
                                  : 'FADE',
                              color: const Color(0xFFA855F7),
                              onTap: ctrl.toggleTransitionMode,
                            ),
                            const SizedBox(width: 8),
                            _ActionChip(
                              icon: Icons.subtitles_rounded,
                              label: 'RÓTULO',
                              color: ctrl.overlayConfig.isVisible
                                  ? const Color(0xFFEF4444)
                                  : Colors.grey.shade400,
                              highlighted: ctrl.overlayConfig.isVisible,
                              onTap: () =>
                                  _showLowerThirdDialog(context, ctrl),
                            ),
                            const SizedBox(width: 8),
                            _ActionChip(
                              icon: ctrl.isRecording
                                  ? Icons.stop_rounded
                                  : Icons.fiber_manual_record_rounded,
                              label: ctrl.isRecording ? 'STOP' : 'REC',
                              color: const Color(0xFFEF4444),
                              highlighted: ctrl.isRecording,
                              onTap: () =>
                                  _handleToggleRecording(context, ctrl),
                            ),
                            const SizedBox(width: 8),
                            _StatusChip(
                              icon: Icons.videocam_rounded,
                              label:
                                  '${ctrl.connectedCount}/${NetworkConstants.maxConnectedCameras}',
                              color: ctrl.connectedCount > 0
                                  ? const Color(0xFF22C55E)
                                  : Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Área Superior (~65%): Monitor EN VIVO solo, o PVW + TAKE + PGM en Modo Estudio
              Expanded(
                flex: 65,
                child: ctrl.studioMode
                    ? Row(
                        children: [
                          Expanded(
                            child: PreviewMonitor(
                              previewRenderer: ctrl.previewRenderer,
                              previewCamera: ctrl.previewCamera,
                              showTelemetry: ctrl.showTelemetry,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: _TakeControlColumn(
                              canTake: ctrl.canTake,
                              transitionMode: ctrl.transitionMode,
                              onTake: ctrl.takePreviewToLive,
                              onToggleTransition: ctrl.toggleTransitionMode,
                            ),
                          ),
                          Expanded(child: programMonitor),
                        ],
                      )
                    : programMonitor,
              ),
              const SizedBox(height: 12),

              // Cuadrícula inferior para hasta 4 cámaras simultáneas (~35%)
              Expanded(
                flex: 35,
                child: Row(
                  children: List.generate(
                    NetworkConstants.maxConnectedCameras,
                    (index) {
                      final cam = ctrl.slots[index];
                      final isLive =
                          cam != null && cam.id == ctrl.activeLiveCameraId;
                      final isPreview = ctrl.studioMode &&
                          cam != null &&
                          !isLive &&
                          cam.id == ctrl.previewCameraId;

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 0 : 6,
                            right: index ==
                                    NetworkConstants.maxConnectedCameras - 1
                                ? 0
                                : 6,
                          ),
                          child: CameraSlotTile(
                            slotIndex: index,
                            camera: cam,
                            isLive: isLive,
                            isPreview: isPreview,
                            isAudioActive:
                                cam != null && ctrl.isCameraAudioActive(cam),
                            showTelemetry: ctrl.showTelemetry,
                            onTap: cam != null
                                ? () => ctrl.onSlotTapped(cam.id)
                                : null,
                            onToggleMute: cam != null
                                ? () => ctrl.toggleCameraMute(cam.id)
                                : null,
                            onRemoteSwitchCamera: cam != null
                                ? () => ctrl.remoteSwitchCamera(cam.id)
                                : null,
                            onRemoteToggleTorch: cam != null
                                ? () => ctrl.remoteToggleTorch(cam.id)
                                : null,
                            onRemoteSelectQuality: cam != null
                                ? (q) => ctrl.remoteSetQuality(cam.id, q)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TakeControlColumn extends StatelessWidget {
  final bool canTake;
  final TransitionMode transitionMode;
  final VoidCallback onTake;
  final VoidCallback onToggleTransition;

  const _TakeControlColumn({
    required this.canTake,
    required this.transitionMode,
    required this.onTake,
    required this.onToggleTransition,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: canTake ? onTake : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white10,
              minimumSize: const Size(88, 66),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_horiz_rounded, size: 22),
                const SizedBox(height: 2),
                Text(
                  transitionMode == TransitionMode.cut ? 'TAKE' : 'FADE',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onToggleTransition,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(88, 34),
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(
              transitionMode == TransitionMode.cut ? 'Modo CUT' : 'Modo FADE',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool highlighted;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? color : color.withAlpha(36),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(130)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: highlighted ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(105)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
