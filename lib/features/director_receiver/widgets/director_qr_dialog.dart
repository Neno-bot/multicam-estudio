import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_constants.dart';

class DirectorQrDialog extends StatelessWidget {
  final String hostIp;
  final int port;
  final int initialTab;

  const DirectorQrDialog({
    super.key,
    required this.hostIp,
    required this.port,
    this.initialTab = 0,
  });

  String get _connectionUri => 'multicam://$hostIp:$port';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: AlertDialog(
        backgroundColor: const Color(0xFF141923),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2_rounded, color: Color(0xFF3B82F6)),
                SizedBox(width: 8),
                Text('Añadir Teléfono Cámara'),
              ],
            ),
            SizedBox(height: 8),
            TabBar(
              tabs: [
                Tab(text: '1. Conectar Cámara'),
                Tab(text: '2. Instalar App'),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          height: 310,
          child: TabBarView(
            children: [
              // Tab 1: Emparejar cámara ya instalada
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: QrImageView(
                      data: _connectionUri,
                      version: QrVersions.auto,
                      size: 185,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    '$hostIp:$port',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'En el mismo Wi-Fi se conecta solo. Si no, escanea este QR desde el icono QR en Modo Cámara.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
                  ),
                ],
              ),

              // Tab 2: Descargar NenoCam Studio en otro teléfono Android
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: QrImageView(
                      data: AppConstants.directArm64ApkUrl,
                      version: QrVersions.auto,
                      size: 185,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Descargar ${AppConstants.appName} (Android)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Escanea con la cámara normal de otro teléfono para bajar e instalar la app al instante.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
