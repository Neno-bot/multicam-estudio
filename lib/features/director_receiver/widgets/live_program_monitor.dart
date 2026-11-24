import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/models/camera_node.dart';
import '../../../core/models/overlay_config.dart';
import '../../../core/models/stream_stats.dart';

class LiveProgramMonitor extends StatelessWidget {
  final RTCVideoRenderer programRenderer;
  final CameraNode? activeCamera;
  final bool isFadingTransition;
  final OverlayConfig overlayConfig;
  final bool isRecording;
  final Duration recordingDuration;
  final bool showTelemetry;

  const LiveProgramMonitor({
    super.key,
    required this.programRenderer,
    required this.activeCamera,
    required this.isFadingTransition,
    required this.overlayConfig,
    required this.isRecording,
    required this.recordingDuration,
    required this.showTelemetry,
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
    final hasLiveFeed = activeCamera != null && activeCamera!.stream != null;
    final stats = activeCamera?.stats;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasLiveFeed ? const Color(0xFFEF4444) : Colors.white12,
          width: hasLiveFeed ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasLiveFeed)
            RTCVideoView(
              programRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            )
          else
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

          // Cortina suave para transición FADE
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: isFadingTransition ? 1.0 : 0.0,
              child: Container(color: Colors.black),
            ),
          ),

          // Etiqueta EN VIVO (PGM) arriba a la izquierda
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
                    color: hasLiveFeed
                        ? const Color(0xFFEF4444)
                        : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 9, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        hasLiveFeed ? 'EN VIVO (PGM)' : 'SIN SEÑAL',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasLiveFeed) ...[
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

          // Indicador REC con reloj arriba a la derecha
          if (isRecording)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
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
            ),

          // Fase 3: HUD de telemetría WebRTC abajo a la derecha
          if (showTelemetry && hasLiveFeed && stats != null)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

          // Overlay Lower Third (Rótulo animado en pantalla)
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
                        left: BorderSide(color: Color(0xFFEF4444), width: 5),
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
        ],
      ),
    );
  }
}
