import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/media_overlay_config.dart';
import '../director_controller.dart';

class MediaManagerDialog extends StatelessWidget {
  const MediaManagerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final imgCfg = ctrl.imageOverlay;

    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        backgroundColor: const Color(0xFF141923),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.perm_media_rounded, color: Color(0xFF3B82F6)),
                SizedBox(width: 8),
                Text('Imágenes y Videos en Vivo'),
              ],
            ),
            SizedBox(height: 8),
            TabBar(
              tabs: [
                Tab(icon: Icon(Icons.image_rounded, size: 18), text: 'Imágenes'),
                Tab(icon: Icon(Icons.movie_rounded, size: 18), text: 'Videos'),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 310,
          child: TabBarView(
            children: [
              // TAB 1: IMÁGENES (Logo en esquina o Placa pantalla completa)
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: ctrl.pickOverlayImage,
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: Text(
                        imgCfg.hasImage
                            ? 'Cambiar imagen de galería'
                            : 'Elegir imagen de galería (PNG/JPG)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (imgCfg.hasImage) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mostrar imagen en EN VIVO'),
                        value: imgCfg.isVisible,
                        onChanged: (v) => ctrl.setImageOverlayVisible(v),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Posición en pantalla:',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<ImageOverlayPlacement>(
                        segments: const [
                          ButtonSegment(
                            value: ImageOverlayPlacement.topRightLogo,
                            label: Text('Logo Der.'),
                          ),
                          ButtonSegment(
                            value: ImageOverlayPlacement.topLeftLogo,
                            label: Text('Logo Izq.'),
                          ),
                          ButtonSegment(
                            value: ImageOverlayPlacement.fullscreenSlide,
                            label: Text('Pantalla'),
                          ),
                        ],
                        selected: {imgCfg.placement},
                        onSelectionChanged: (set) =>
                            ctrl.setImageOverlayPlacement(set.first),
                      ),
                      if (imgCfg.placement !=
                          ImageOverlayPlacement.fullscreenSlide) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text(
                              'Tamaño:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                value: imgCfg.sizeFactor,
                                min: 0.12,
                                max: 0.36,
                                onChanged: ctrl.setImageOverlaySize,
                              ),
                            ),
                          ],
                        ),
                      ],
                      TextButton.icon(
                        onPressed: ctrl.clearImageOverlay,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        label: const Text(
                          'Quitar imagen',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Puedes subir tu logo (PNG transparente) para las esquinas o una placa/anuncio a pantalla completa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // TAB 2: VIDEOS LOCALES (MP4 en el Monitor EN VIVO)
              SingleChildScrollView(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        await ctrl.pickAndPlayVideo();
                      },
                      icon: const Icon(Icons.video_library_rounded),
                      label: Text(
                        ctrl.hasLocalVideo
                            ? 'Elegir otro video (MP4)'
                            : 'Elegir video de galería y reproducir',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (ctrl.hasLocalVideo) ...[
                      Text(
                        ctrl.isPlayingLocalVideo
                            ? 'Estado: VIDEO AL AIRE EN MONITOR EN VIVO'
                            : 'Estado: Video pausado / listo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ctrl.isPlayingLocalVideo
                              ? const Color(0xFF22C55E)
                              : Colors.amber,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filledTonal(
                            onPressed: ctrl.toggleLocalVideoPlayPause,
                            icon: Icon(
                              ctrl.isVideoControllerPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            tooltip: 'Reproducir / Pausar',
                          ),
                          IconButton.filledTonal(
                            onPressed: ctrl.restartLocalVideo,
                            icon: const Icon(Icons.replay_rounded),
                            tooltip: 'Reiniciar video',
                          ),
                          IconButton.filledTonal(
                            onPressed: ctrl.toggleLocalVideoLoop,
                            icon: Icon(
                              Icons.repeat_rounded,
                              color: ctrl.isLocalVideoLooping
                                  ? const Color(0xFF22C55E)
                                  : null,
                            ),
                            tooltip: 'Repetir en bucle',
                          ),
                          IconButton.filledTonal(
                            onPressed: ctrl.toggleLocalVideoMute,
                            icon: Icon(
                              ctrl.isLocalVideoMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                            ),
                            tooltip: 'Silenciar video',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () {
                          ctrl.stopLocalVideoAndReturnToCameras();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.videocam_rounded),
                        label: const Text('Quitar video y volver a cámaras'),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Reproduce intros, anuncios o videos MP4 directamente en el Monitor EN VIVO. Al tocar cualquier cámara abajo volverás al instante a esa cámara.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }
}
