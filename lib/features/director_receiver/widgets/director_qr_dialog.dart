import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DirectorQrDialog extends StatelessWidget {
  final String hostIp;
  final int port;

  const DirectorQrDialog({
    super.key,
    required this.hostIp,
    required this.port,
  });

  String get _connectionUri => 'multicam://$hostIp:$port';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF141923),
      title: const Row(
        children: [
          Icon(Icons.qr_code_2_rounded, color: Color(0xFF3B82F6)),
          SizedBox(width: 8),
          Text('Conectar Cámara por QR / IP'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
              data: _connectionUri,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            '$hostIp:$port',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Escanea este código desde el teléfono si la red bloquea descubrimiento automático.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
