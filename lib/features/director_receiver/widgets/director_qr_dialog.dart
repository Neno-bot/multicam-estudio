import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_constants.dart';

/// Diálogo responsivo para añadir cámaras por QR o instalar la app.
/// Se adapta automáticamente a teléfonos en horizontal (2 columnas) para que el QR
/// SIEMPRE salga completo y nunca se recorte.
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
    final screen = MediaQuery.sizeOf(context);
    final isCompactHeight = screen.height < 520;
    final dialogWidth =
        isCompactHeight ? (screen.width * 0.84).clamp(420.0, 560.0) : 380.0;
    final contentHeight =
        isCompactHeight ? (screen.height * 0.56).clamp(170.0, 230.0) : 310.0;

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Dialog(
        backgroundColor: const Color(0xFF141923),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: dialogWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabecera compacta con botón cerrar en la esquina superior derecha
                Row(
                  children: [
                    const Icon(
                      Icons.qr_code_2_rounded,
                      color: Color(0xFF3B82F6),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Añadir Teléfono Cámara',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 30),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const SizedBox(
                  height: 36,
                  child: TabBar(
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: [
                      Tab(text: '1. Conectar Cámara'),
                      Tab(text: '2. Instalar App'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: contentHeight,
                  child: TabBarView(
                    children: [
                      _QrTabContent(
                        qrData: _connectionUri,
                        headline: '$hostIp:$port',
                        subtitle:
                            'En el mismo Wi-Fi se conecta solo. Si no, abre Modo Cámara en el otro teléfono y escanea este QR.',
                        isHorizontal: isCompactHeight,
                      ),
                      _QrTabContent(
                        qrData: AppConstants.directArm64ApkUrl,
                        headline: 'Descargar ${AppConstants.appName}',
                        subtitle:
                            'Escanea con la cámara normal de otro teléfono Android para bajar e instalar la app al instante.',
                        isHorizontal: isCompactHeight,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QrTabContent extends StatelessWidget {
  final String qrData;
  final String headline;
  final String subtitle;
  final bool isHorizontal;

  const _QrTabContent({
    required this.qrData,
    required this.headline,
    required this.subtitle,
    required this.isHorizontal,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (isHorizontal) {
          final qrSize = (constraints.maxHeight - 24).clamp(115.0, 190.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SelectableText(
                        headline,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        final qrSize = (constraints.maxHeight - 110).clamp(130.0, 195.0);
        return SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
