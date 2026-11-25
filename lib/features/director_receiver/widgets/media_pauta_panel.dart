import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/media_cue_item.dart';
import '../../../core/models/media_overlay_config.dart';
import '../director_controller.dart';

/// Bandeja de Pauta Switcher (a la palma de la mano):
/// Permite cargar múltiples imágenes y videos y lanzarlos al Monitor EN VIVO en 1 toque
/// con la transición activa (CUT / FADE), igual que cambiar de cámara.
class MediaPautaPanel extends StatelessWidget {
  const MediaPautaPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final cues = ctrl.mediaCues;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111621),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera compacta con botones +IMG (múltiple) y +VID
          Row(
            children: [
              const Icon(
                Icons.dashboard_customize_rounded,
                size: 14,
                color: Color(0xFF60A5FA),
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'PAUTA MEDIA',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              _QuickAddButton(
                icon: Icons.add_photo_alternate_rounded,
                label: '+IMG',
                color: const Color(0xFF3B82F6),
                onTap: ctrl.addImagesToPauta,
              ),
              const SizedBox(width: 4),
              _QuickAddButton(
                icon: Icons.video_call_rounded,
                label: '+VID',
                color: const Color(0xFFA855F7),
                onTap: ctrl.addVideoToPauta,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Lista / Cuadrícula táctil de Imágenes y Videos pautados
          Expanded(
            child: cues.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.collections_rounded,
                          size: 26,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Toca +IMG para elegir varias imágenes\no +VID para videos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 1.35,
                    ),
                    itemCount: cues.length,
                    itemBuilder: (context, index) {
                      final cue = cues[index];
                      final isLive = ctrl.isCueActive(cue.id);
                      return _MediaCueTile(
                        cue: cue,
                        isLive: isLive,
                        onTap: () => ctrl.triggerMediaCue(cue.id),
                        onCyclePlacement: cue.type == MediaCueType.image
                            ? () => ctrl.cycleCueImagePlacement(cue.id)
                            : null,
                        onRemove: () => ctrl.removeMediaCue(cue.id),
                      );
                    },
                  ),
          ),

          // Controles rápidos si hay un video reproduciéndose en vivo
          if (ctrl.isPlayingLocalVideo) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _TinyIconBtn(
                    icon: ctrl.isVideoControllerPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: 'Pausar / Reproducir',
                    onTap: ctrl.toggleLocalVideoPlayPause,
                  ),
                  _TinyIconBtn(
                    icon: Icons.replay_rounded,
                    tooltip: 'Reiniciar',
                    onTap: ctrl.restartLocalVideo,
                  ),
                  _TinyIconBtn(
                    icon: Icons.repeat_rounded,
                    color: ctrl.isLocalVideoLooping
                        ? const Color(0xFF22C55E)
                        : Colors.white70,
                    tooltip: 'Bucle',
                    onTap: ctrl.toggleLocalVideoLoop,
                  ),
                  _TinyIconBtn(
                    icon: ctrl.isLocalVideoMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: ctrl.isLocalVideoMuted
                        ? Colors.redAccent
                        : Colors.white70,
                    tooltip: 'Silenciar video',
                    onTap: ctrl.toggleLocalVideoMute,
                  ),
                  _TinyIconBtn(
                    icon: Icons.close_rounded,
                    color: Colors.redAccent,
                    tooltip: 'Quitar video',
                    onTap: ctrl.stopLocalVideoAndReturnToCameras,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaCueTile extends StatelessWidget {
  final MediaCueItem cue;
  final bool isLive;
  final VoidCallback onTap;
  final VoidCallback? onCyclePlacement;
  final VoidCallback onRemove;

  const _MediaCueTile({
    required this.cue,
    required this.isLive,
    required this.onTap,
    required this.onRemove,
    this.onCyclePlacement,
  });

  String _placementTag() {
    if (cue.type == MediaCueType.video) return 'VID';
    switch (cue.imagePlacement) {
      case ImageOverlayPlacement.fullscreenSlide:
        return 'PLACA';
      case ImageOverlayPlacement.topRightLogo:
        return 'LOGO D';
      case ImageOverlayPlacement.topLeftLogo:
        return 'LOGO I';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = cue.isCornerLogo
        ? const Color(0xFF3B82F6)
        : const Color(0xFFEF4444);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2232),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isLive ? activeColor : Colors.white12,
            width: isLive ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cue.type == MediaCueType.image)
              Image.file(
                File(cue.filePath),
                fit: BoxFit.cover,
                cacheWidth: 260,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 22),
                ),
              )
            else
              Container(
                color: const Color(0xFF1E1B3A),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 28,
                    color: Color(0xFFC084FC),
                  ),
                ),
              ),

            // Botón modo (Placa / Logo) arriba a la izquierda + borrar arriba a la derecha
            Positioned(
              top: 3,
              left: 3,
              child: GestureDetector(
                onTap: onCyclePlacement,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(185),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _placementTag(),
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(185),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),

            // Etiqueta inferior + badge EN VIVO
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                color: Colors.black.withAlpha(190),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cue.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          cue.isCornerLogo ? 'ON' : 'LIVE',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAddButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(42),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _TinyIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
