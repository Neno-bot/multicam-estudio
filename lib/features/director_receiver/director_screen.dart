import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/network_constants.dart';
import '../../core/models/media_overlay_config.dart';
import '../../core/models/overlay_config.dart';
import '../../core/utils/device_utils.dart';
import 'director_controller.dart';
import 'widgets/camera_slot_tile.dart';
import 'widgets/director_qr_dialog.dart';
import 'widgets/live_program_monitor.dart';
import 'widgets/live_stream_dialog.dart';
import 'widgets/lower_third_dialog.dart';
import 'widgets/media_manager_dialog.dart';
import 'widgets/media_pauta_panel.dart';
import 'widgets/preview_monitor.dart';
import 'widgets/record_gallery_dialog.dart';

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

  void _showQrDialog(
    BuildContext context,
    DirectorController ctrl, {
    int initialTab = 0,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => DirectorQrDialog(
        hostIp: ctrl.localIp,
        port: NetworkConstants.signalingPort,
        initialTab: initialTab,
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

  void _showMediaDialog(BuildContext context, DirectorController ctrl) {
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: ctrl,
        child: const MediaManagerDialog(),
      ),
    );
  }

  Future<void> _showLiveStreamDialog(
    BuildContext context,
    DirectorController ctrl,
  ) async {
    final config = await showDialog<LiveStreamConfig>(
      context: context,
      builder: (_) => LiveStreamDialog(
        isCurrentlyStreaming: ctrl.isRtmpLive,
        currentStatusMessage: ctrl.rtmpStatusMessage,
        onStopStream: ctrl.stopRtmpLive,
      ),
    );

    if (config == null) return;
    await ctrl.startRtmpLive(
      rtmpUrl: config.fullRtmpUrl,
      bitrateKbps: config.bitrateKbps,
      enterCleanMode: config.enterCleanMode,
    );

    if (context.mounted && ctrl.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.lastError!)),
      );
    }
  }

  Future<void> _handleToggleRecording(
    BuildContext context,
    DirectorController ctrl,
  ) async {
    if (ctrl.isRecording) {
      await ctrl.stopGalleryRecording();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Guardando grabación en tu Galería...'),
          ),
        );
      }
      return;
    }

    final config = await showDialog<GalleryRecordConfig>(
      context: context,
      builder: (_) => const RecordGalleryDialog(),
    );
    if (config == null || !context.mounted) return;

    await ctrl.startGalleryRecording(
      width: config.width,
      height: config.height,
      bitrateKbps: config.bitrateKbps,
      audioEnabled: config.audioEnabled,
      enterCleanMode: config.enterCleanMode,
    );

    if (context.mounted && ctrl.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.consumeLastError()!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();

    // Mostrar notificación inmediata cuando la grabación termina de guardarse en la Galería
    if (ctrl.lastSavedRecordingMessage != null) {
      final savedMsg = ctrl.consumeLastSavedRecordingMessage()!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 5),
            content: Text('✅ $savedMsg'),
          ),
        );
      });
    }

    final programMonitor = LiveProgramMonitor(
      programRenderer: ctrl.programRenderer,
      activeCamera: ctrl.activeLiveCamera,
      isFadingTransition: ctrl.isFadingTransition,
      overlayConfig: ctrl.overlayConfig,
      imageOverlay: ctrl.imageOverlay,
      overlayLayers: ctrl.overlayLayers,
      overlayVideoControllerFor: ctrl.overlayVideoControllerFor,
      watermarkConfig: ctrl.watermarkConfig,
      localVideoController: ctrl.localVideoController,
      isPlayingLocalVideo: ctrl.isPlayingLocalVideo,
      isRecording: ctrl.isRecording,
      recordingDuration: ctrl.recordingDuration,
      isRtmpLive: ctrl.isRtmpLive,
      rtmpBitrateKbps: ctrl.rtmpBitrateKbps,
      showTelemetry: ctrl.showTelemetry,
      cleanMode: ctrl.cleanBroadcastMode,
    );

    // MODO PANTALLA LIMPIA (Ideal para transmitir a YouTube Live / Facebook Live)
    if (ctrl.cleanBroadcastMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            programMonitor,
            // Barra flotante discreta abajo a la derecha (Cámaras 1-4 + Pauta rápida + Salir)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(165),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...List.generate(NetworkConstants.maxConnectedCameras, (i) {
                      final cam = ctrl.slots[i];
                      final ready = cam != null && cam.stream != null;
                      final live = ready &&
                          !ctrl.isPlayingLocalVideo &&
                          cam.id == ctrl.activeLiveCameraId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: ready
                              ? () => ctrl.selectLiveCamera(cam.id)
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 28,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: live
                                  ? const Color(0xFFEF4444)
                                  : ready
                                      ? Colors.white24
                                      : Colors.white10,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(
                              'C${i + 1}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: ready ? Colors.white : Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (ctrl.mediaCues.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(width: 1, height: 18, color: Colors.white24),
                      const SizedBox(width: 4),
                      ...ctrl.mediaCues.take(4).map((cue) {
                        final active = ctrl.isCueActive(cue.id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: () => ctrl.triggerMediaCue(cue.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFF3B82F6)
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                cue.label,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    if (ctrl.isRecording) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _handleToggleRecording(context, ctrl),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stop_rounded, size: 13),
                              SizedBox(width: 2),
                              Text(
                                'STOP REC',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Salir de Pantalla Limpia',
                      onPressed: ctrl.toggleCleanBroadcastMode,
                      icon: const Icon(Icons.fullscreen_exit_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              // Cabecera de control profesional de NenoCam Studio
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Salir del Modo Director',
                    ),
                    const SizedBox(width: 2),
                    Text(
                      AppConstants.appName.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 10),

                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          children: [
                            _ActionChip(
                              icon: ctrl.isRtmpLive
                                  ? Icons.podcasts_rounded
                                  : Icons.live_tv_rounded,
                              label: ctrl.isRtmpLive
                                  ? 'EN VIVO (YT/FB)'
                                  : 'TRANSMITIR',
                              color: const Color(0xFFEF4444),
                              highlighted: ctrl.isRtmpLive,
                              onTap: () => _showLiveStreamDialog(context, ctrl),
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: ctrl.isRecording
                                  ? Icons.stop_rounded
                                  : Icons.fiber_manual_record_rounded,
                              label: ctrl.isRecording ? 'STOP REC' : 'GRABAR',
                              color: const Color(0xFFF97316),
                              highlighted: ctrl.isRecording,
                              onTap: () =>
                                  _handleToggleRecording(context, ctrl),
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.dashboard_customize_rounded,
                              label: 'PAUTA (${ctrl.mediaCues.length})',
                              color: const Color(0xFF3B82F6),
                              highlighted: ctrl.showPautaPanel &&
                                  ctrl.sideTab == DirectorSideTab.pauta,
                              onTap: () {
                                if (ctrl.showPautaPanel &&
                                    ctrl.sideTab == DirectorSideTab.pauta) {
                                  ctrl.togglePautaPanel();
                                } else {
                                  ctrl.setSideTab(DirectorSideTab.pauta);
                                }
                              },
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.layers_rounded,
                              label: ctrl.activeOverlayCount > 0
                                  ? 'CAPAS (${ctrl.activeOverlayCount} ON)'
                                  : 'CAPAS',
                              color: const Color(0xFF22C55E),
                              highlighted: ctrl.activeOverlayCount > 0 ||
                                  (ctrl.showPautaPanel &&
                                      ctrl.sideTab == DirectorSideTab.overlays),
                              onTap: ctrl.openOverlaysTab,
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.auto_awesome_motion_rounded,
                              label: ctrl.transitionMode == TransitionMode.cut
                                  ? 'CUT'
                                  : 'FADE',
                              color: const Color(0xFFA855F7),
                              onTap: ctrl.toggleTransitionMode,
                            ),
                            const SizedBox(width: 7),
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
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: ctrl.audioMixMode == AudioMixMode.tabletOnly
                                  ? Icons.mic_rounded
                                  : ctrl.audioMixMode == AudioMixMode.afv
                                      ? Icons.hearing_rounded
                                      : Icons.graphic_eq_rounded,
                              label: 'AUDIO: ${ctrl.audioModeLabel}',
                              color: ctrl.audioMixMode == AudioMixMode.tabletOnly
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFF59E0B),
                              onTap: ctrl.cycleAudioMixMode,
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.qr_code_2_rounded,
                              label: 'AÑADIR CAM',
                              color: const Color(0xFF60A5FA),
                              onTap: () => _showQrDialog(context, ctrl),
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.fullscreen_rounded,
                              label: 'LIMPIO',
                              color: const Color(0xFF14B8A6),
                              onTap: ctrl.toggleCleanBroadcastMode,
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: ctrl.studioMode
                                  ? Icons.view_column_rounded
                                  : Icons.crop_landscape_rounded,
                              label: ctrl.studioMode ? 'ESTUDIO' : 'DIRECTO',
                              color: const Color(0xFF14B8A6),
                              highlighted: ctrl.studioMode,
                              onTap: ctrl.toggleStudioMode,
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.tune_rounded,
                              label: 'AJUSTES MEDIA',
                              color: Colors.grey.shade400,
                              onTap: () => _showMediaDialog(context, ctrl),
                            ),
                            const SizedBox(width: 7),
                            _ActionChip(
                              icon: Icons.speed_rounded,
                              label: 'STATS',
                              color: const Color(0xFF60A5FA),
                              highlighted: ctrl.showTelemetry,
                              onTap: ctrl.toggleTelemetry,
                            ),
                            const SizedBox(width: 7),
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
              const SizedBox(height: 8),

              // Área Principal de Producción:
              // Izquierda (~67%): Monitor EN VIVO arriba + 4 Cámaras compactas abajo
              // Derecha (~33%): Dos cuadros independientes deslizables -> IMÁGENES arriba + VIDEOS abajo
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: ctrl.showPautaPanel ? 67 : 100,
                      child: Column(
                        children: [
                          // Monitor EN VIVO (o PVW + TAKE + PGM en Modo Estudio)
                          Expanded(
                            flex: 66,
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: _TakeControlColumn(
                                          canTake: ctrl.canTake,
                                          transitionMode: ctrl.transitionMode,
                                          onTake: ctrl.takePreviewToLive,
                                          onToggleTransition:
                                              ctrl.toggleTransitionMode,
                                        ),
                                      ),
                                      Expanded(child: programMonitor),
                                    ],
                                  )
                                : programMonitor,
                          ),
                          const SizedBox(height: 8),

                          // Cuadrícula compacta para las 4 cámaras debajo del monitor
                          Expanded(
                            flex: 34,
                            child: Row(
                              children: List.generate(
                                NetworkConstants.maxConnectedCameras,
                                (index) {
                                  final cam = ctrl.slots[index];
                                  final isLive = cam != null &&
                                      !ctrl.isPlayingLocalVideo &&
                                      cam.id == ctrl.activeLiveCameraId;
                                  final isPreview = ctrl.studioMode &&
                                      cam != null &&
                                      !isLive &&
                                      cam.id == ctrl.previewCameraId;

                                  return Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: index == 0 ? 0 : 3,
                                        right: index ==
                                                NetworkConstants
                                                        .maxConnectedCameras -
                                                    1
                                            ? 0
                                            : 3,
                                      ),
                                      child: CameraSlotTile(
                                        slotIndex: index,
                                        camera: cam,
                                        isLive: isLive,
                                        isPreview: isPreview,
                                        isAudioActive: cam != null &&
                                            ctrl.isCameraAudioActive(cam),
                                        showTelemetry: ctrl.showTelemetry,
                                        onTap: cam != null
                                            ? () => ctrl.onSlotTapped(cam.id)
                                            : null,
                                        onAddCameraTap: () =>
                                            _showQrDialog(context, ctrl),
                                        onToggleMute: cam != null
                                            ? () =>
                                                ctrl.toggleCameraMute(cam.id)
                                            : null,
                                        onRemoteSwitchCamera: cam != null
                                            ? () => ctrl
                                                .remoteSwitchCamera(cam.id)
                                            : null,
                                        onRemoteToggleTorch: cam != null
                                            ? () =>
                                                ctrl.remoteToggleTorch(cam.id)
                                            : null,
                                        onRemoteSelectQuality: cam != null
                                            ? (q) => ctrl.remoteSetQuality(
                                                cam.id, q)
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
                    if (ctrl.showPautaPanel) ...[
                      const SizedBox(width: 8),
                      const Expanded(
                        flex: 33,
                        child: MediaPautaPanel(),
                      ),
                    ],
                  ],
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
      width: 82,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: canTake ? onTake : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white10,
              minimumSize: const Size(78, 58),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_horiz_rounded, size: 20),
                const SizedBox(height: 2),
                Text(
                  transitionMode == TransitionMode.cut ? 'TAKE' : 'FADE',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.9,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onToggleTransition,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(78, 32),
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            child: Text(
              transitionMode == TransitionMode.cut ? 'CUT' : 'FADE',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
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
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(130)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: highlighted ? Colors.white : color,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(105)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
