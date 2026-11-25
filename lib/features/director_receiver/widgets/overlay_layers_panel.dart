import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/overlay_layer_item.dart';
import '../director_controller.dart';

/// Sección independiente 'CAPAS / OVERLAYS' (Downstream Keyer):
/// - Slot fijo exclusivo para Marca de Agua / Logo (Nivel Superior) con opacidad, escala y esquina.
/// - Lista deslizable de Plantillas / Cintillos (PNG / GIF / WebP / WebM con canal alfa)
///   con interruptor individual ON/OFF (fade suave), opacidad y posición.
/// - Nunca interrumpe cámaras, pauta media ni audio en vivo.
class OverlayLayersPanel extends StatelessWidget {
  const OverlayLayersPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final overlays = ctrl.overlayLayers;
    final watermark = ctrl.watermarkConfig;

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
          // Cabecera + botón '+ OVERLAY' (PNG / GIF / WebM)
          Row(
            children: [
              const Icon(
                Icons.layers_rounded,
                size: 14,
                color: Color(0xFF22C55E),
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'CAPAS / OVERLAYS',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Material(
                color: const Color(0xFF3B82F6).withAlpha(46),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: ctrl.addOverlayTemplates,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_to_photos_rounded,
                          size: 12.5,
                          color: Color(0xFF60A5FA),
                        ),
                        SizedBox(width: 3),
                        Text(
                          '+ OVERLAY',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF60A5FA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Lista deslizable: Marca de Agua fija (arriba) + Plantillas subidas
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                _WatermarkSlotCard(
                  config: watermark,
                  onPick: ctrl.pickWatermarkImage,
                  onToggle: ctrl.setWatermarkVisible,
                  onOpacityChanged: ctrl.setWatermarkOpacity,
                  onScaleChanged: ctrl.setWatermarkScale,
                  onCycleCorner: ctrl.cycleWatermarkCorner,
                  onClear: ctrl.clearWatermark,
                ),
                const SizedBox(height: 6),
                if (overlays.isEmpty)
                  InkWell(
                    onTap: ctrl.addOverlayTemplates,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171E2C),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 20,
                            color: Colors.blue.shade300,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sube plantillas o cintillos transparentes\nPNG / GIF / WebP / WebM (1920x1080)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 9.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...List.generate(overlays.length, (index) {
                    final item = overlays[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _OverlayTemplateCard(
                        item: item,
                        layerNumber: index + 1,
                        onToggle: (v) => ctrl.toggleOverlayLayer(item.id, v),
                        onOpacityChanged: (v) =>
                            ctrl.setOverlayOpacity(item.id, v),
                        onCyclePosition: () =>
                            ctrl.cycleOverlayPosition(item.id),
                        onRemove: () => ctrl.removeOverlayLayer(item.id),
                      ),
                    );
                  }),
              ],
            ),
          ),

          // Nota de independencia al pie
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 11,
                color: Colors.amber.shade300,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Se superponen sin interrumpir cámaras, pauta ni audio.',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WatermarkSlotCard extends StatelessWidget {
  final WatermarkConfig config;
  final VoidCallback onPick;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onScaleChanged;
  final VoidCallback onCycleCorner;
  final VoidCallback onClear;

  const _WatermarkSlotCard({
    required this.config,
    required this.onPick,
    required this.onToggle,
    required this.onOpacityChanged,
    required this.onScaleChanged,
    required this.onCycleCorner,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = config.hasImage && config.isVisible;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF161E2E),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isLive ? const Color(0xFF22C55E) : Colors.white12,
          width: isLive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Miniatura o botón subir logo
              GestureDetector(
                onTap: onPick,
                child: _CheckerThumb(
                  child: config.hasImage
                      ? Image.file(
                          File(config.filePath!),
                          fit: BoxFit.contain,
                          cacheWidth: 160,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            size: 16,
                          ),
                        )
                      : const Icon(
                          Icons.branding_watermark_rounded,
                          size: 18,
                          color: Color(0xFF60A5FA),
                        ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MARCA DE AGUA / LOGO',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withAlpha(40),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'CAPA SUPERIOR',
                            style: TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4ADE80),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onPick,
                          child: Text(
                            config.hasImage ? 'Cambiar' : 'Subir PNG',
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF60A5FA),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 26,
                child: Transform.scale(
                  scale: 0.72,
                  child: Switch(
                    value: isLive,
                    activeColor: Colors.white,
                    activeTrackColor: const Color(0xFF22C55E),
                    onChanged: config.hasImage ? onToggle : (_) => onPick(),
                  ),
                ),
              ),
            ],
          ),
          if (config.hasImage) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Opac.',
                  style: TextStyle(fontSize: 8.5, color: Colors.white70),
                ),
                Expanded(
                  child: SliderTheme(
                    data: _compactSliderTheme(context),
                    child: Slider(
                      value: config.opacity,
                      min: 0.15,
                      max: 1.0,
                      onChanged: onOpacityChanged,
                    ),
                  ),
                ),
                Text(
                  '${(config.opacity * 100).round()}%',
                  style: const TextStyle(fontSize: 8.5, color: Colors.white70),
                ),
              ],
            ),
            Row(
              children: [
                const Text(
                  'Escala',
                  style: TextStyle(fontSize: 8.5, color: Colors.white70),
                ),
                Expanded(
                  child: SliderTheme(
                    data: _compactSliderTheme(context),
                    child: Slider(
                      value: config.scale,
                      min: 0.08,
                      max: 0.35,
                      onChanged: onScaleChanged,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onCycleCorner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      config.corner.label,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OverlayTemplateCard extends StatelessWidget {
  final OverlayLayerItem item;
  final int layerNumber;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onOpacityChanged;
  final VoidCallback onCyclePosition;
  final VoidCallback onRemove;

  const _OverlayTemplateCard({
    required this.item,
    required this.layerNumber,
    required this.onToggle,
    required this.onOpacityChanged,
    required this.onCyclePosition,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF171E2C),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: item.isActive ? const Color(0xFF22C55E) : Colors.white12,
          width: item.isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _CheckerThumb(
                child: item.format.isVideo
                    ? const Icon(
                        Icons.movie_filter_rounded,
                        size: 18,
                        color: Color(0xFFC084FC),
                      )
                    : Image.file(
                        File(item.filePath),
                        fit: BoxFit.contain,
                        cacheWidth: 160,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.layers_outlined,
                          size: 16,
                        ),
                      ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            item.format.badgeLabel,
                            style: const TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Capa $layerNumber',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        if (item.isActive) ...[
                          const SizedBox(width: 4),
                          const Text(
                            '• ON',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4ADE80),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 26,
                child: Transform.scale(
                  scale: 0.72,
                  child: Switch(
                    value: item.isActive,
                    activeColor: Colors.white,
                    activeTrackColor: const Color(0xFF22C55E),
                    onChanged: onToggle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const Text(
                'Opac.',
                style: TextStyle(fontSize: 8.5, color: Colors.white70),
              ),
              Expanded(
                child: SliderTheme(
                  data: _compactSliderTheme(context),
                  child: Slider(
                    value: item.opacity,
                    min: 0.1,
                    max: 1.0,
                    onChanged: onOpacityChanged,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onCyclePosition,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.position.label,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckerThumb extends StatelessWidget {
  final Widget child;

  const _CheckerThumb({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF0E131D),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }
}

SliderThemeData _compactSliderTheme(BuildContext context) {
  return SliderTheme.of(context).copyWith(
    trackHeight: 2.2,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
    activeTrackColor: const Color(0xFF3B82F6),
    inactiveTrackColor: Colors.white12,
    thumbColor: const Color(0xFF60A5FA),
  );
}
