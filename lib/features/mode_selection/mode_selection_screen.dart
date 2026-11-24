import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/device_utils.dart';
import '../camera_emitter/camera_emitter_screen.dart';
import '../director_receiver/director_screen.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  Future<void> _openCameraMode(BuildContext context) async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final granted = statuses[Permission.camera]?.isGranted == true &&
        statuses[Permission.microphone]?.isGranted == true;

    if (!context.mounted) return;

    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se necesitan permisos de cámara y micrófono para transmitir.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CameraEmitterScreen()),
    );
  }

  void _openDirectorMode(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DirectorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = DeviceUtils.isTablet(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    size: 52,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MultiCam Studio',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecciona el rol de este dispositivo en la red Wi-Fi local',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                  ),
                  const SizedBox(height: 36),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sideBySide = constraints.maxWidth > 620;
                      final cards = [
                        _RoleCard(
                          icon: Icons.smartphone_rounded,
                          title: 'Modo Cámara (Teléfono)',
                          subtitle:
                              'Busca automáticamente al Director en tu Wi-Fi y transmite video de baja latencia.',
                          accentColor: const Color(0xFF3B82F6),
                          recommended: !isTablet,
                          onTap: () => _openCameraMode(context),
                        ),
                        _RoleCard(
                          icon: Icons.tablet_mac_rounded,
                          title: 'Modo Director (Tablet)',
                          subtitle:
                              'Recibe hasta 4 cámaras simultáneas con monitor EN VIVO y conmutación táctil.',
                          accentColor: const Color(0xFFEF4444),
                          recommended: isTablet,
                          onTap: () => _openDirectorMode(context),
                        ),
                      ];

                      if (sideBySide) {
                        return Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 20),
                            Expanded(child: cards[1]),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 16),
                          cards[1],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final bool recommended;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF141923),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: recommended ? accentColor : Colors.white12,
            width: recommended ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 30),
                ),
                if (recommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'RECOMENDADO',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade400, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
