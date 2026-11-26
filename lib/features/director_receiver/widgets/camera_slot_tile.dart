import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/models/camera_node.dart';
import '../../../core/models/video_quality_profile.dart';

class CameraSlotTile extends StatelessWidget {
  final int slotIndex;
  final CameraNode? camera;
  final bool isLive;
  final bool isPreview;
  final bool isAudioActive;
  final bool showTelemetry;
  final VoidCallback? onTap;
  final VoidCallback? onAddCameraTap;
  final VoidCallback? onToggleMute;
  final VoidCallback? onRemoteSwitchCamera;
  final VoidCallback? onRemoteToggleTorch;
  final ValueChanged<VideoQualityProfile>? onRemoteSelectQuality;

  const CameraSlotTile({
    super.key,
    required this.slotIndex,
    required this.camera,
    required this.isLive,
    required this.isPreview,
    required this.isAudioActive,
    required this.showTelemetry,
    this.onTap,
    this.onAddCameraTap,
    this.onToggleMute,
    this.onRemoteSwitchCamera,
    this.onRemoteToggleTorch,
    this.onRemoteSelectQuality,
  });

  @override
  Widget build(BuildContext context) {
    final isConnected = camera != null && camera!.stream != null;

    final borderColor = isLive
        ? const Color(0xFFEF4444)
        : isPreview
            ? const Color(0xFF22C55E)
            : isConnected
                ? Colors.white24
                : Colors.white10;

    return GestureDetector(
      onTap: isConnected ? onTap : (camera == null ? onAddCameraTap : null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: const Color(0xFF141923),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: (isLive || isPreview) ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showCompactTelemetry =
                isConnected &&
                showTelemetry &&
                camera!.stats != null &&
                constraints.maxWidth >= 175;

            return Stack(
              fit: StackFit.expand,
              children: [
                if (isConnected)
                  RTCVideoView(
                    camera!.renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          camera != null
                              ? Icons.sync_rounded
                              : Icons.qr_code_2_rounded,
                          color: camera != null
                              ? Colors.amber
                              : const Color(0xFF60A5FA),
                          size: 20,
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            camera != null
                                ? 'Conectando...'
                                : '+ AÑADIR QR',
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Badge compacto de telemetría solo cuando el slot tiene ancho suficiente (evita solaparse con controles en teléfono)
                if (showCompactTelemetry)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(175),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${camera!.stats!.resolutionLabel} ${camera!.stats!.fps.round()}fps',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),

            // Controles rápidos remotos (Mute / Calidad / Flip / Linterna)
            if (isConnected)
              Positioned(
                top: 4,
                right: 4,
                left: 4,
                child: Align(
                  alignment: Alignment.topRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniControlButton(
                          icon: camera!.isAudioMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: camera!.isAudioMuted
                              ? Colors.redAccent
                              : isAudioActive
                                  ? const Color(0xFF22C55E)
                                  : Colors.white70,
                          tooltip: camera!.isAudioMuted
                              ? 'Activar audio'
                              : 'Silenciar cámara',
                          onPressed: onToggleMute,
                        ),
                        const SizedBox(width: 3),
                        PopupMenuButton<VideoQualityProfile>(
                          tooltip: 'Cambiar calidad remota',
                          padding: EdgeInsets.zero,
                          color: const Color(0xFF141923),
                          onSelected: onRemoteSelectQuality,
                          itemBuilder: (_) => VideoQualityProfile.values
                              .map(
                                (p) => PopupMenuItem(
                                  value: p,
                                  child: Row(
                                    children: [
                                      Icon(
                                        camera!.quality == p
                                            ? Icons.check_rounded
                                            : Icons.hd_outlined,
                                        size: 16,
                                        color: camera!.quality == p
                                            ? const Color(0xFF3B82F6)
                                            : Colors.white70,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(p.label),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(165),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              camera!.quality.id,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF60A5FA),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        _MiniControlButton(
                          icon: Icons.cameraswitch_rounded,
                          color: Colors.white,
                          tooltip: 'Voltear cámara remotamente',
                          onPressed: onRemoteSwitchCamera,
                        ),
                        const SizedBox(width: 3),
                        _MiniControlButton(
                          icon: camera!.isTorchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: camera!.isTorchOn
                              ? Colors.amber
                              : Colors.white70,
                          tooltip: 'Alternar linterna remota',
                          onPressed: onRemoteToggleTorch,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Barra inferior con nombre e indicador PGM / PVW
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: Colors.black.withAlpha(185),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        camera != null
                            ? 'CAM ${slotIndex + 1} • ${camera!.name}'
                            : 'CAM ${slotIndex + 1}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'EN VIVO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    else if (isPreview)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PVW',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MiniControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  const _MiniControlButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withAlpha(165),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(3.5),
            child: Icon(icon, size: 13.5, color: color),
          ),
        ),
      ),
    );
  }
}
