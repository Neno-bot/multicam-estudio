import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/device_utils.dart';
import '../../services/update/update_check_service.dart';
import '../camera_emitter/camera_emitter_screen.dart';
import '../director_receiver/director_screen.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  final UpdateCheckService _updateService = UpdateCheckService();
  AppUpdateInfo? _updateInfo;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _checkUpdates(silent: true);
  }

  Future<void> _checkUpdates({bool silent = false}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    final info = await _updateService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _updateInfo = info;
      _checkingUpdate = false;
    });

    if (!silent) {
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo verificar actualizaciones (revisa tu internet).'),
          ),
        );
      } else if (!info.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ya tienes la última versión (v${AppConstants.appVersion}).',
            ),
          ),
        );
      }
    }
  }

  Future<void> _downloadUpdate(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace de descarga.')),
      );
    }
  }

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

  Future<void> _openDirectorMode(BuildContext context) async {
    // Solicitar micrófono y notificaciones para la Tablet Director (audio local + YouTube/Facebook Live)
    await [Permission.microphone, Permission.notification].request();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DirectorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = DeviceUtils.isTablet(context);
    final hasUpdate = _updateInfo?.hasUpdate == true;

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
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Producción multicámara en vivo • v${AppConstants.appVersion}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  ),

                  // Banner de actualización disponible
                  if (hasUpdate) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withAlpha(32),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF22C55E).withAlpha(140),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.system_update_rounded,
                            color: Color(0xFF22C55E),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Nueva versión disponible: v${_updateInfo!.latestVersion}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () =>
                                _downloadUpdate(_updateInfo!.downloadUrl),
                            child: const Text('Actualizar'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sideBySide = constraints.maxWidth > 620;
                      final cards = [
                        _RoleCard(
                          icon: Icons.smartphone_rounded,
                          title: 'Modo Cámara (Teléfono)',
                          subtitle:
                              'Se conecta sola a la Tablet por Wi-Fi y envía video en vivo (micrófono silenciado por defecto).',
                          accentColor: const Color(0xFF3B82F6),
                          recommended: !isTablet,
                          onTap: () => _openCameraMode(context),
                        ),
                        _RoleCard(
                          icon: Icons.tablet_mac_rounded,
                          title: 'Modo Director (Tablet)',
                          subtitle:
                              'Controla hasta 4 cámaras, imágenes, videos locales, audio de la Tablet y transmisión a YouTube / Facebook Live.',
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
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: _checkingUpdate
                          ? null
                          : () => _checkUpdates(silent: false),
                      icon: _checkingUpdate
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        _checkingUpdate
                            ? 'Buscando actualizaciones...'
                            : 'Buscar actualización',
                      ),
                    ),
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
