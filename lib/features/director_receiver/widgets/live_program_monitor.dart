import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/camera_node.dart';
import '../../../core/models/media_overlay_config.dart';
import '../../../core/models/overlay_config.dart';
import '../../../core/models/overlay_layer_item.dart';
import '../../../core/models/stream_stats.dart';

class LiveProgramMonitor extends StatelessWidget {
  final RTCVideoRenderer programRenderer;
  final CameraNode? activeCamera;
  final bool isFadingTransition;
  final OverlayConfig overlayConfig;
  final ImageOverlayConfig imageOverlay;
  final List<OverlayLayerItem> overlayLayers;
  final VideoPlayerController? Function(String overlayId)?
      overlayVideoControllerFor;
  final WatermarkConfig watermarkConfig;
  final VideoPlayerController? localVideoController;
  final bool isPlayingLocalVideo;
  final bool isRecording;
  final Duration recordingDuration;
  final bool isRtmpLive;
  final String? rtmpBitrateKbps;
  final bool showTelemetry;
  final bool cleanMode;

  const LiveProgramMonitor({
    super.key,
    required this.programRenderer,
    required this.activeCamera,
    required this.isFadingTransition,
    required this.overlayConfig,
    required this.imageOverlay,
    required this.localVideoController,
    required this.isPlayingLocalVideo,
    required this.isRecording,
    required this.recordingDuration,
    required this.isRtmpLive,
    required this.rtmpBitrateKbps,
    required this.showTelemetry,
    this.overlayLayers = const [],
    this.overlayVideoControllerFor,
    this.watermarkConfig = const WatermarkConfig(),
    this.cleanMode = false,
  });

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Color _healthColor(SignalHealth health) {
    switch (health) {
      case SignalHealth.good:
        return const Color(0xFF22C55E);
      case SignalHealth.fair:
        return const Color(0xFFF59E0B);
      case SignalHealth.poor:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCameraFeed = activeCamera != null && activeCamera!.stream != null;
    final hasVideoFeed = isPlayingLocalVideo &&
        localVideoController != null &&
        localVideoController!.value.isInitialized;
    final hasFullscreenImage = imageOverlay.isVisible &&
        imageOverlay.hasImage &&
        imageOverlay.placement == ImageOverlayPlacement.fullscreenSlide;
    final hasCornerLogo = imageOverlay.isVisible &&
        imageOverlay.hasImage &&
        imageOverlay.placement != ImageOverlayPlacement.fullscreenSlide;
    final hasAnyLiveFeed = hasCameraFeed || hasVideoFeed || hasFullscreenImage;
    final stats = activeCamera?.stats;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: cleanMode ? BorderRadius.zero : BorderRadius.circular(14),
        border: cleanMode
            ? null
            : Border.all(
                color:
                    hasAnyLiveFeed ? const Color(0xFFEF4444) : Colors.white12,
                width: hasAnyLiveFeed ? 2.5 : 1,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final logoWidth =
              (constraints.maxWidth * imageOverlay.sizeFactor).clamp(64.0, 260.0);
          final watermarkWidth =
              (constraints.maxWidth * watermarkConfig.scale).clamp(48.0, 280.0);
          final watermarkTopOffset = cleanMode ? 16.0 : 48.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              // === NIVEL 1 (BASE): Cámara activa o Video/Placa de Pauta Media ===
              if (hasVideoFeed)
                Center(
                  child: AspectRatio(
                    aspectRatio: localVideoController!.value.aspectRatio > 0
                        ? localVideoController!.value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(localVideoController!),
                  ),
                )
              else if (hasCameraFeed)
                RTCVideoView(
                  programRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                )
              else if (!hasFullscreenImage)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.live_tv_rounded,
                      size: 54,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ESPERANDO SEÑAL DE CÁMARAS EN LA RED WI-FI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),

              // Placa a pantalla completa de Pauta Media (Nivel Base)
              if (hasFullscreenImage)
                Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: Image.file(
                    File(imageOverlay.filePath!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),

              // Cortina FADE del Nivel Base (las capas DSK y Marca de Agua permanecen firmes encima)
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: isFadingTransition ? 1.0 : 0.0,
                  child: Container(color: Colors.black),
                ),
              ),

              // === NIVEL 2 (MEDIO — DOWNSTREAM KEYER): Plantillas / Cintillos con transparencia ===
              ...overlayLayers.map((layer) {
                final vc = layer.format.isVideo
                    ? overlayVideoControllerFor?.call(layer.id)
                    : null;
                final canRender = !layer.format.isVideo ||
                    (vc != null && vc.value.isInitialized);

                return IgnorePointer(
                  key: ValueKey('dsk_${layer.id}'),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOut,
                    opacity: (layer.isActive && canRender) ? layer.opacity : 0.0,
                    child: Align(
                      alignment: layer.position.alignment,
                      child: layer.format.isVideo
                          ? (vc != null && vc.value.isInitialized
                              ? AspectRatio(
                                  aspectRatio: vc.value.aspectRatio > 0
                                      ? vc.value.aspectRatio
                                      : 16 / 9,
                                  child: VideoPlayer(vc),
                                )
                              : const SizedBox.shrink())
                          : Image.file(
                              File(layer.filePath),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                    ),
                  ),
                );
              }),

              // Logo de esquina rápido desde Pauta (compatibilidad)
              if (hasCornerLogo)
                Positioned(
                  top: cleanMode ? 18 : 54,
                  right: imageOverlay.placement ==
                          ImageOverlayPlacement.topRightLogo
                      ? 18
                      : null,
                  left: imageOverlay.placement ==
                          ImageOverlayPlacement.topLeftLogo
                      ? 18
                      : null,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: logoWidth,
                      child: Image.file(
                        File(imageOverlay.filePath!),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),

              // Rótulo de texto Lower Third (Nivel Medio)
              Positioned(
                left: 18,
                bottom: 18,
                child: IgnorePointer(
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    offset: overlayConfig.isVisible
                        ? Offset.zero
                        : const Offset(-0.25, 0),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      opacity: overlayConfig.isVisible ? 1.0 : 0.0,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withAlpha(225),
                          borderRadius: BorderRadius.circular(8),
                          border: const Border(
                            left: BorderSide(
                              color: Color(0xFFEF4444),
                              width: 5,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (overlayConfig.title.isNotEmpty)
                              Text(
                                overlayConfig.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            if (overlayConfig.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                overlayConfig.subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade300,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // === NIVEL 3 (SUPERIOR): Marca de Agua / Logo fija con opacidad y escala ===
              if (watermarkConfig.hasImage)
                Positioned(
                  top: (watermarkConfig.corner == WatermarkCorner.topRight ||
                          watermarkConfig.corner == WatermarkCorner.topLeft)
                      ? watermarkTopOffset
                      : null,
                  bottom:
                      (watermarkConfig.corner == WatermarkCorner.bottomRight ||
                              watermarkConfig.corner ==
                                  WatermarkCorner.bottomLeft)
                          ? 16.0
                          : null,
                  right: (watermarkConfig.corner == WatermarkCorner.topRight ||
                          watermarkConfig.corner ==
                              WatermarkCorner.bottomRight)
                      ? 16.0
                      : null,
                  left: (watermarkConfig.corner == WatermarkCorner.topLeft ||
                          watermarkConfig.corner == WatermarkCorner.bottomLeft)
                      ? 16.0
                      : null,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      opacity: watermarkConfig.isVisible
                          ? watermarkConfig.opacity
                          : 0.0,
                      child: SizedBox(
                        width: watermarkWidth,
                        child: Image.file(
                          File(watermarkConfig.filePath!),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),

              // 6. Badges técnicos del Director (ocultos en Clean Broadcast Mode)
              if (!cleanMode) ...[
                Positioned(
                  top: 12,
                  left: 12,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: hasAnyLiveFeed
                              ? const Color(0xFFEF4444)
                              : Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 9,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasFullscreenImage
                                  ? 'PLACA EN VIVO'
                                  : hasVideoFeed
                                      ? 'VIDEO EN VIVO'
                                      : hasCameraFeed
                                          ? 'EN VIVO (PGM)'
                                          : 'SIN SEÑAL',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasCameraFeed &&
                          !hasVideoFeed &&
                          !hasFullscreenImage) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(180),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'CAM ${activeCamera!.slotIndex + 1} • ${activeCamera!.name}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Badges RTMP LIVE y REC arriba a la derecha
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRtmpLive)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.sensors_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                rtmpBitrateKbps != null
                                    ? 'STREAM ${rtmpBitrateKbps!}k'
                                    : 'STREAM LIVE',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(195),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFEF4444),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.fiber_manual_record,
                                size: 13,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'REC ${_formatDuration(recordingDuration)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // HUD de telemetría WebRTC abajo a la derecha
                if (showTelemetry &&
                    hasCameraFeed &&
                    !hasVideoFeed &&
                    stats != null)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(190),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.signal_cellular_alt_rounded,
                            size: 14,
                            color: _healthColor(stats.health),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            stats.compactSummary,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
