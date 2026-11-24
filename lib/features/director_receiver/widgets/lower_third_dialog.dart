import 'package:flutter/material.dart';

import '../../../core/models/overlay_config.dart';

class LowerThirdDialog extends StatefulWidget {
  final OverlayConfig initialConfig;

  const LowerThirdDialog({super.key, required this.initialConfig});

  @override
  State<LowerThirdDialog> createState() => _LowerThirdDialogState();
}

class _LowerThirdDialogState extends State<LowerThirdDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late bool _isVisible;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialConfig.title);
    _subtitleCtrl = TextEditingController(text: widget.initialConfig.subtitle);
    _isVisible = widget.initialConfig.isVisible;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141923),
      title: const Row(
        children: [
          Icon(Icons.subtitles_rounded, color: Color(0xFFEF4444)),
          SizedBox(width: 8),
          Text('Rótulo en Pantalla (Lower Third)'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar en Monitor EN VIVO'),
              value: _isVisible,
              onChanged: (val) => setState(() => _isVisible = val),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Título principal',
                hintText: 'Ej: Dra. Sofía Méndez',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtitleCtrl,
              decoration: const InputDecoration(
                labelText: 'Subtítulo / Cargo',
                hintText: 'Ej: Invitada Especial • En Vivo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              OverlayConfig(
                isVisible: _isVisible,
                title: _titleCtrl.text.trim(),
                subtitle: _subtitleCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
