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

typedef CaptureRectCallback = void Function(
  int left,
  int top,
  int right,
  int bottom,
);

/// Monitor Principal EN VIVO (PGM):
/// - La barra técnica (EN VIVO, CAM, REC, STREAM, telemetría, LLENAR/AJUSTAR) vive ARRIBA
///   fuera del cuadro rojo, de modo que DENTRO del cuadro rojo solo existe video limpio.
/// - El motor nativo captura EXCLUSIVAMENTE el interior del cuadro rojo (16:9 completo,
///   sin bordes negros, sin botones del Director y sin notificaciones del teléfono).
class LiveProgramMonitor extends StatefulWidget {
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
  final bool fillFrame;
  final VoidCallback? onToggleFillFrame;
  final CaptureRectCallback? onCaptureRectChanged;
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
    this.fillFrame = true,
    this.onToggleFillFrame,
    this.onCaptureRectChanged,
    this.cleanMode = false,
  });

  @override
  State<LiveProgramMonitor> createState() => _LiveProgramMonitorState();
}

class _LiveProgramMonitorState extends State<LiveProgramMonitor> {
  final GlobalKey _canvasKey = GlobalKey();
  int _lastL = -1;
  int _lastT = -1;
  int _lastR = -1;
  int _lastB = -1;

  void _scheduleRectReport() {
    if (widget.onCaptureRectChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _canvasKey.currentContext;
      if (ctx == null) return;
      final renderObj = ctx.findRenderObject();
      if (renderObj is! RenderBox || !renderObj.hasSize) return;

      final topLeft = renderObj.localToGlobal(Offset.zero);
      final size = renderObj.size;
      if (size.width < 16 || size.height < 16) return;

      final dpr = MediaQuery.devicePixelRatioOf(ctx);
      final l = (topLeft.dx * dpr).round();
      final t = (topLeft.dy * dpr).round();
      final r = ((topLeft.dx + size.width) * dpr).round();
      final b = ((topLeft.dy + size.height) * dpr).round();

      if (l != _lastL || t != _lastT || r != _lastR || b != _lastB) {
        _lastL = l;
        _lastT = t;
        _lastR = r;
        _lastB = b;
        widget.onCaptureRectChanged!(l, t, r, b);
      }
    });
  }

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
    _scheduleRectReport();

    final hasCameraFeed =
        widget.activeCamera != null && widget.activeCamera!.stream != null;
    final hasVideoFeed = widget.isPlayingLocalVideo &&
        widget.localVideoController != null &&
        widget.localVideoController!.value.isInitialized;
    final hasFullscreenImage = widget.imageOverlay.isVisible &&
        widget.imageOverlay.hasImage &&
        widget.imageOverlay.placement == ImageOverlayPlacement.fullscreenSlide;
    final hasCornerLogo = widget.imageOverlay.isVisible &&
        widget.imageOverlay.hasImage &&
        widget.imageOverlay.placement != ImageOverlayPlacement.fullscreenSlide;
    final hasAnyLiveFeed = hasCameraFeed || hasVideoFeed || hasFullscreenImage;
    final stats = widget.activeCamera?.stats;

    final pureCanvas = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
            widget.cleanMode ? BorderRadius.zero : BorderRadius.circular(10),
        border: widget.cleanMode
            ? null
            : Border.all(
                color:
                    hasAnyLiveFeed ? const Color(0xFFEF4444) : Colors.white12,
                width: hasAnyLiveFeed ? 2.5 : 1,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: KeyedSubtree(
        key: _canvasKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final logoWidth =
                (constraints.maxWidth * widget.imageOverlay.sizeFactor)
                    .clamp(64.0, 260.0);
            final watermarkWidth =
                (constraints.maxWidth * widget.watermarkConfig.scale)
                    .clamp(48.0, 280.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                // === NIVEL 1 (BASE): Cámara activa o Video/Placa a cuadro completo ===
                if (hasVideoFeed)
                  _buildVideoLayer(widget.localVideoController!)
                else if (hasCameraFeed)
                  RTCVideoView(
                    widget.programRenderer,
                    objectFit: widget.fillFrame
                        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                        : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                else if (!hasFullscreenImage)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.live_tv_rounded,
                        size: 46,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ESPERANDO SEÑAL DE CÁMARAS EN LA RED WI-FI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.9,
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
                      File(widget.imageOverlay.filePath!),
                      width: double.infinity,
                      height: double.infinity,
                      fit: widget.fillFrame ? BoxFit.cover : BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),

                // Cortina FADE del Nivel Base (Capas DSK y Marca de Agua quedan firmes encima)
                IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: widget.isFadingTransition ? 1.0 : 0.0,
                    child: Container(color: Colors.black),
                  ),
                ),

                // === NIVEL 2 (MEDIO — DOWNSTREAM KEYER): Plantillas / Cintillos con transparencia ===
                ...widget.overlayLayers.map((layer) {
                  final vc = layer.format.isVideo
                      ? widget.overlayVideoControllerFor?.call(layer.id)
                      : null;
                  final canRender = !layer.format.isVideo ||
                      (vc != null && vc.value.isInitialized);

                  return IgnorePointer(
                    key: ValueKey('dsk_${layer.id}'),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      opacity:
                          (layer.isActive && canRender) ? layer.opacity : 0.0,
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
                    top: 14,
                    right: widget.imageOverlay.placement ==
                            ImageOverlayPlacement.topRightLogo
                        ? 14
                        : null,
                    left: widget.imageOverlay.placement ==
                            ImageOverlayPlacement.topLeftLogo
                        ? 14
                        : null,
                    child: IgnorePointer(
                      child: SizedBox(
                        width: logoWidth,
                        child: Image.file(
                          File(widget.imageOverlay.filePath!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),

                // Rótulo de texto Lower Third (Nivel Medio)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: IgnorePointer(
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      offset: widget.overlayConfig.isVisible
                          ? Offset.zero
                          : const Offset(-0.25, 0),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        opacity: widget.overlayConfig.isVisible ? 1.0 : 0.0,
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
                              if (widget.overlayConfig.title.isNotEmpty)
                                Text(
                                  widget.overlayConfig.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              if (widget.overlayConfig.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.overlayConfig.subtitle,
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
                if (widget.watermarkConfig.hasImage)
                  Positioned(
                    top: (widget.watermarkConfig.corner ==
                                WatermarkCorner.topRight ||
                            widget.watermarkConfig.corner ==
                                WatermarkCorner.topLeft)
                        ? 14.0
                        : null,
                    bottom: (widget.watermarkConfig.corner ==
                                WatermarkCorner.bottomRight ||
                            widget.watermarkConfig.corner ==
                                WatermarkCorner.bottomLeft)
                        ? 14.0
                        : null,
                    right: (widget.watermarkConfig.corner ==
                                WatermarkCorner.topRight ||
                            widget.watermarkConfig.corner ==
                                WatermarkCorner.bottomRight)
                        ? 14.0
                        : null,
                    left: (widget.watermarkConfig.corner ==
                                WatermarkCorner.topLeft ||
                            widget.watermarkConfig.corner ==
                                WatermarkCorner.bottomLeft)
                        ? 14.0
                        : null,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeInOut,
                        opacity: widget.watermarkConfig.isVisible
                            ? widget.watermarkConfig.opacity
                            : 0.0,
                        child: SizedBox(
                          width: watermarkWidth,
                          child: Image.file(
                            File(widget.watermarkConfig.filePath!),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (widget.cleanMode) {
      return pureCanvas;
    }

    // En Modo Director: barra técnica delgada FUERA del cuadro rojo (arriba)
    // para que la grabación y transmisión salgan 100% limpias sin ningún badge encima.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: hasAnyLiveFeed
                      ? const Color(0xFFEF4444)
                      : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, size: 7, color: Colors.white),
                    const SizedBox(width: 4),
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
                        fontSize: 9.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasCameraFeed && !hasVideoFeed && !hasFullscreenImage) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'CAM ${widget.activeCamera!.slotIndex + 1} • ${widget.activeCamera!.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (hasCameraFeed && !hasVideoFeed && !hasFullscreenImage)
                const Spacer(),
              if (widget.isRtmpLive)
                Container(
                  margin: const EdgeInsets.only(right: 5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.rtmpBitrateKbps != null
                        ? 'LIVE ${widget.rtmpBitrateKbps!}k'
                        : 'LIVE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
              if (widget.isRecording)
                Container(
                  margin: const EdgeInsets.only(right: 5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withAlpha(45),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFF97316)),
                  ),
                  child: Text(
                    '● REC ${_formatDuration(widget.recordingDuration)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      color: Color(0xFFFDBA74),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              if (widget.showTelemetry &&
                  hasCameraFeed &&
                  !hasVideoFeed &&
                  stats != null) ...[
                Icon(
                  Icons.signal_cellular_alt_rounded,
                  size: 12,
                  color: _healthColor(stats.health),
                ),
                const SizedBox(width: 3),
                Text(
                  stats.compactSummary,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white60,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.onToggleFillFrame != null)
                InkWell(
                  onTap: widget.onToggleFillFrame,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.fillFrame ? 'LLENAR' : 'AJUSTAR',
                      style: const TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Expanded(child: pureCanvas),
      ],
    );
  }

  Widget _buildVideoLayer(VideoPlayerController vc) {
    final aspect = vc.value.aspectRatio > 0 ? vc.value.aspectRatio : 16 / 9;
    if (widget.fillFrame) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: aspect * 100,
            height: 100,
            child: VideoPlayer(vc),
          ),
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: VideoPlayer(vc),
      ),
    );
  }
}
