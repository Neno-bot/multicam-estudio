import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/network_constants.dart';

class ManualConnectResult {
  final String host;
  final int port;
  final String cameraName;

  const ManualConnectResult({
    required this.host,
    required this.port,
    required this.cameraName,
  });
}

class ManualConnectDialog extends StatefulWidget {
  final String initialCameraName;
  final String? initialHost;
  final int initialPort;

  const ManualConnectDialog({
    super.key,
    required this.initialCameraName,
    this.initialHost,
    this.initialPort = NetworkConstants.signalingPort,
  });

  @override
  State<ManualConnectDialog> createState() => _ManualConnectDialogState();
}

class _ManualConnectDialogState extends State<ManualConnectDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialCameraName);
    _hostCtrl = TextEditingController(text: widget.initialHost ?? '');
    _portCtrl = TextEditingController(text: widget.initialPort.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _DirectorQrScannerPage()),
    );
    if (scanned == null || !mounted) return;

    final parsed = _parseConnectionUri(scanned);
    if (parsed != null) {
      setState(() {
        _hostCtrl.text = parsed.$1;
        _portCtrl.text = parsed.$2.toString();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código QR no válido. Usa el QR del Modo Director.'),
        ),
      );
    }
  }

  (String, int)? _parseConnectionUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('multicam://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.host.isNotEmpty) {
        return (
          uri.host,
          uri.hasPort ? uri.port : NetworkConstants.signalingPort,
        );
      }
    }
    final parts = trimmed.split(':');
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      final port = parts.length > 1
          ? int.tryParse(parts[1]) ?? NetworkConstants.signalingPort
          : NetworkConstants.signalingPort;
      return (parts.first, port);
    }
    return null;
  }

  void _submit() {
    final host = _hostCtrl.text.trim();
    final port =
        int.tryParse(_portCtrl.text.trim()) ?? NetworkConstants.signalingPort;
    final name = _nameCtrl.text.trim().isEmpty
        ? widget.initialCameraName
        : _nameCtrl.text.trim();

    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa la IP local del Director.')),
      );
      return;
    }

    Navigator.of(context).pop(
      ManualConnectResult(host: host, port: port, cameraName: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141923),
      title: const Text('Conexión Manual / QR'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Escanear QR del Director'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre de esta cámara',
                hintText: 'Ej: Plano General',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'IP del Director',
                hintText: 'Ej: 192.168.1.42',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puerto',
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
          onPressed: _submit,
          child: const Text('Conectar'),
        ),
      ],
    );
  }
}

class _DirectorQrScannerPage extends StatefulWidget {
  const _DirectorQrScannerPage();

  @override
  State<_DirectorQrScannerPage> createState() => _DirectorQrScannerPageState();
}

class _DirectorQrScannerPageState extends State<_DirectorQrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR del Director')),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (_handled) return;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              _handled = true;
              Navigator.of(context).pop(value);
              break;
            }
          }
        },
      ),
    );
  }
}
