import 'package:flutter/material.dart';

class GalleryRecordConfig {
  final int width;
  final int height;
  final int bitrateKbps;
  final bool audioEnabled;
  final bool enterCleanMode;

  const GalleryRecordConfig({
    required this.width,
    required this.height,
    required this.bitrateKbps,
    required this.audioEnabled,
    required this.enterCleanMode,
  });
}

/// Diálogo para grabar la producción completa directamente a la Galería
/// del dispositivo principal (Tablet o Teléfono) sin transmitir en vivo.
class RecordGalleryDialog extends StatefulWidget {
  const RecordGalleryDialog({super.key});

  @override
  State<RecordGalleryDialog> createState() => _RecordGalleryDialogState();
}

class _RecordGalleryDialogState extends State<RecordGalleryDialog> {
  bool _is1080p = false;
  bool _audioEnabled = true;
  bool _enterCleanMode = false;

  void _start() {
    Navigator.of(context).pop(
      GalleryRecordConfig(
        width: _is1080p ? 1920 : 1280,
        height: _is1080p ? 1080 : 720,
        bitrateKbps: _is1080p ? 6000 : 4000,
        audioEnabled: _audioEnabled,
        enterCleanMode: _enterCleanMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final isWide = screen.width >= 560;

    return Dialog(
      backgroundColor: const Color(0xFF141923),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 520 : 400,
          maxHeight: screen.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.save_alt_rounded,
                    color: Color(0xFFEF4444),
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Grabar y Guardar en Galería',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Graba EXCLUSIVAMENTE el cuadro rojo EN VIVO a pantalla completa (sin botones, sin notificaciones de WhatsApp y sin aviso de compartir pantalla). Al detener, el MP4 se guarda directo en tu Galería (Movies/NenoCam Studio).',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade300,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Calidad MP4:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('720p HD (Recomendado)'),
                    selected: !_is1080p,
                    onSelected: (_) => setState(() => _is1080p = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('1080p Full HD'),
                    selected: _is1080p,
                    onSelected: (_) => setState(() => _is1080p = true),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Grabar micrófono del dispositivo principal',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                value: _audioEnabled,
                onChanged: (v) => setState(() => _audioEnabled = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Expandir monitor a pantalla completa (opcional)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Déjalo desactivado para ver tus cámaras, pauta y capas mientras grabas SOLO el cuadro rojo limpio.',
                  style: TextStyle(fontSize: 10.5),
                ),
                value: _enterCleanMode,
                onChanged: (v) => setState(() => _enterCleanMode = v),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _start,
                    icon: const Icon(Icons.fiber_manual_record_rounded, size: 18),
                    label: const Text(
                      'INICIAR GRABACIÓN',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
