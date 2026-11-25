import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/media_cue_item.dart';
import '../../../core/models/media_overlay_config.dart';
import '../director_controller.dart';
import 'overlay_layers_panel.dart';

/// Columna derecha con pestañas independientes:
/// - PAUTA MEDIA: dos cuadros separados y deslizables (IMÁGENES arriba + VIDEOS abajo)
/// - CAPAS / OVERLAYS: Downstream Keyer independiente (Marca de Agua fija + Plantillas PNG/GIF/WebM)
class MediaPautaPanel extends StatelessWidget {
  const MediaPautaPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final isOverlaysTab = ctrl.sideTab == DirectorSideTab.overlays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selector superior de pestaña: PAUTA MEDIA | CAPAS / OVERLAYS
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF111621),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SideTabPill(
                  icon: Icons.dashboard_customize_rounded,
                  label: 'PAUTA',
                  badgeCount: ctrl.mediaCues.length,
                  selected: !isOverlaysTab,
                  accentColor: const Color(0xFF3B82F6),
                  onTap: () => ctrl.setSideTab(DirectorSideTab.pauta),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _SideTabPill(
                  icon: Icons.layers_rounded,
                  label: 'CAPAS',
                  badgeCount: ctrl.activeOverlayCount,
                  badgeLive: ctrl.activeOverlayCount > 0,
                  selected: isOverlaysTab,
                  accentColor: const Color(0xFF22C55E),
                  onTap: () => ctrl.setSideTab(DirectorSideTab.overlays),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        Expanded(
          child: isOverlaysTab
              ? const OverlayLayersPanel()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 54,
                      child: _MediaSectionBox(
                        title: 'IMÁGENES',
                        icon: Icons.photo_library_rounded,
                        accentColor: const Color(0xFF3B82F6),
                        addLabel: '+IMG',
                        addIcon: Icons.add_photo_alternate_rounded,
                        emptyHint: 'Toca +IMG para\nelegir varias fotos',
                        cues: ctrl.imageCues,
                        onAdd: ctrl.addImagesToPauta,
                        isCueActive: ctrl.isCueActive,
                        onTriggerCue: ctrl.triggerMediaCue,
                        onCyclePlacement: ctrl.cycleCueImagePlacement,
                        onRemoveCue: ctrl.removeMediaCue,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Expanded(
                      flex: 46,
                      child: _MediaSectionBox(
                        title: 'VIDEOS',
                        icon: Icons.video_library_rounded,
                        accentColor: const Color(0xFFA855F7),
                        addLabel: '+VID',
                        addIcon: Icons.video_call_rounded,
                        emptyHint: 'Toca +VID para\nagregar videos',
                        cues: ctrl.videoCues,
                        onAdd: ctrl.addVideoToPauta,
                        isCueActive: ctrl.isCueActive,
                        onTriggerCue: ctrl.triggerMediaCue,
                        onRemoveCue: ctrl.removeMediaCue,
                        footer: ctrl.isPlayingLocalVideo
                            ? _VideoTransportBar(ctrl: ctrl)
                            : null,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SideTabPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badgeCount;
  final bool badgeLive;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _SideTabPill({
    required this.icon,
    required this.label,
    required this.badgeCount,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    this.badgeLive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accentColor.withAlpha(56) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? accentColor.withAlpha(180) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 12.5,
                color: selected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : Colors.white60,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: badgeLive ? const Color(0xFF22C55E) : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: badgeLive ? Colors.black : Colors.white70,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaSectionBox extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String addLabel;
  final IconData addIcon;
  final String emptyHint;
  final List<MediaCueItem> cues;
  final VoidCallback onAdd;
  final bool Function(String cueId) isCueActive;
  final ValueChanged<String> onTriggerCue;
  final ValueChanged<String>? onCyclePlacement;
  final ValueChanged<String> onRemoveCue;
  final Widget? footer;

  const _MediaSectionBox({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.addLabel,
    required this.addIcon,
    required this.emptyHint,
    required this.cues,
    required this.onAdd,
    required this.isCueActive,
    required this.onTriggerCue,
    required this.onRemoveCue,
    this.onCyclePlacement,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111621),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera de sección (IMÁGENES o VIDEOS) + botón rápido
          Row(
            children: [
              Icon(icon, size: 13.5, color: accentColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  cues.isEmpty ? title : '$title (${cues.length})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              _QuickAddButton(
                icon: addIcon,
                label: addLabel,
                color: accentColor,
                onTap: onAdd,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Cuadrícula deslizable verticalmente (2 columnas por fila)
          Expanded(
            child: cues.isEmpty
                ? InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: accentColor.withAlpha(150),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            emptyHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 10,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                      childAspectRatio: 1.6,
                    ),
                    itemCount: cues.length,
                    itemBuilder: (context, index) {
                      final cue = cues[index];
                      final isLive = isCueActive(cue.id);
                      return _MediaCueTile(
                        cue: cue,
                        isLive: isLive,
                        onTap: () => onTriggerCue(cue.id),
                        onCyclePlacement: cue.type == MediaCueType.image &&
                                onCyclePlacement != null
                            ? () => onCyclePlacement!(cue.id)
                            : null,
                        onRemove: () => onRemoveCue(cue.id),
                      );
                    },
                  ),
          ),

          if (footer != null) ...[
            const SizedBox(height: 5),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _VideoTransportBar extends StatelessWidget {
  final DirectorController ctrl;

  const _VideoTransportBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(7),
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
            color: ctrl.isLocalVideoMuted ? Colors.redAccent : Colors.white70,
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
                  child: Icon(Icons.broken_image_outlined, size: 20),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF271D47), Color(0xFF161329)],
                  ),
                ),
                child: Center(
                  child: Icon(
                    isLive
                        ? Icons.graphic_eq_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 24,
                    color: isLive
                        ? const Color(0xFFEF4444)
                        : const Color(0xFFC084FC),
                  ),
                ),
              ),

            // Botón modo (Placa / Logo) o etiqueta VID arriba a la izquierda
            Positioned(
              top: 3,
              left: 3,
              child: GestureDetector(
                onTap: onCyclePlacement,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(185),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _placementTag(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            // Botón borrar arriba a la derecha
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
                    size: 11,
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                color: Colors.black.withAlpha(190),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cue.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
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
                            fontSize: 7.5,
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.5, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
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
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
