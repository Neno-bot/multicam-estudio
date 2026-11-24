import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/models/camera_node.dart';

/// Monitor PREVIO (PVW) para Modo Estudio.
/// Permite inspeccionar una cámara antes de enviarla al aire con el botón TAKE.
class PreviewMonitor extends StatelessWidget {
  final RTCVideoRenderer previewRenderer;
  final CameraNode? previewCamera;
  final bool showTelemetry;

  const PreviewMonitor({
    super.key,
    required this.previewRenderer,
    required this.previewCamera,
    required this.showTelemetry,
  });

  @override
  Widget build(BuildContext context) {
    final hasPreview = previewCamera != null && previewCamera!.stream != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPreview ? const Color(0xFF22C55E) : Colors.white12,
          width: hasPreview ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPreview)
            RTCVideoView(
              previewRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.preview_rounded,
                  size: 46,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(height: 10),
                Text(
                  'TOCA UNA CÁMARA PARA CARGAR PREVIO (PVW)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
              ],
            ),

          // Etiqueta PREVIO (PVW) arriba a la izquierda
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: hasPreview
                        ? const Color(0xFF22C55E)
                        : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PREVIO (PVW)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.7,
                      color: Colors.black,
                    ),
                  ),
                ),
                if (hasPreview) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(180),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'CAM ${previewCamera!.slotIndex + 1} • ${previewCamera!.name}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // HUD de telemetría opcional en PVW
          if (showTelemetry && hasPreview && previewCamera!.stats != null)
            Positioned(
              left: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(185),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  previewCamera!.stats!.compactSummary,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
