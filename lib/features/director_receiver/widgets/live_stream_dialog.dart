import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/media_overlay_config.dart';

class LiveStreamConfig {
  final StreamPlatform platform;
  final String fullRtmpUrl;
  final int bitrateKbps;
  final bool enterCleanMode;

  const LiveStreamConfig({
    required this.platform,
    required this.fullRtmpUrl,
    required this.bitrateKbps,
    required this.enterCleanMode,
  });
}

class LiveStreamDialog extends StatefulWidget {
  final bool isCurrentlyStreaming;
  final String? currentStatusMessage;
  final VoidCallback onStopStream;

  const LiveStreamDialog({
    super.key,
    required this.isCurrentlyStreaming,
    this.currentStatusMessage,
    required this.onStopStream,
  });

  @override
  State<LiveStreamDialog> createState() => _LiveStreamDialogState();
}

class _LiveStreamDialogState extends State<LiveStreamDialog> {
  StreamPlatform _platform = StreamPlatform.youtube;
  late final TextEditingController _serverCtrl;
  late final TextEditingController _keyCtrl;
  int _bitrateKbps = 2500;
  bool _enterCleanMode = true;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController(text: AppConstants.youtubeRtmpBase);
    _keyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _selectPlatform(StreamPlatform platform) {
    setState(() {
      _platform = platform;
      switch (platform) {
        case StreamPlatform.youtube:
          _serverCtrl.text = AppConstants.youtubeRtmpBase;
          break;
        case StreamPlatform.facebook:
          _serverCtrl.text = AppConstants.facebookRtmpsBase;
          break;
        case StreamPlatform.custom:
          _serverCtrl.text = 'rtmp://';
          break;
      }
    });
  }

  void _start() {
    final server = _serverCtrl.text.trim();
    final key = _keyCtrl.text.trim();

    if (server.isEmpty || (key.isEmpty && _platform != StreamPlatform.custom)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pega tu Clave de transmisión (Stream Key).'),
        ),
      );
      return;
    }

    final normalizedServer =
        server.endsWith('/') || key.isEmpty ? server : '$server/';
    final fullUrl = '$normalizedServer$key';

    Navigator.of(context).pop(
      LiveStreamConfig(
        platform: _platform,
        fullRtmpUrl: fullUrl,
        bitrateKbps: _bitrateKbps,
        enterCleanMode: _enterCleanMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCurrentlyStreaming) {
      return AlertDialog(
        backgroundColor: const Color(0xFF141923),
        title: const Row(
          children: [
            Icon(Icons.podcasts_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Transmisión EN VIVO activa'),
          ],
        ),
        content: Text(
          widget.currentStatusMessage ??
              'Transmitiendo hacia YouTube / Facebook Live con el micrófono de la Tablet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Seguir en vivo'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () {
              widget.onStopStream();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Finalizar En Vivo'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF141923),
      title: const Row(
        children: [
          Icon(Icons.live_tv_rounded, color: Color(0xFFEF4444)),
          SizedBox(width: 8),
          Text('Transmitir a YouTube / Facebook'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<StreamPlatform>(
                segments: const [
                  ButtonSegment(
                    value: StreamPlatform.youtube,
                    label: Text('YouTube'),
                    icon: Icon(Icons.play_circle_fill_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: StreamPlatform.facebook,
                    label: Text('Facebook'),
                    icon: Icon(Icons.facebook_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: StreamPlatform.custom,
                    label: Text('Otro RTMP'),
                  ),
                ],
                selected: {_platform},
                onSelectionChanged: (s) => _selectPlatform(s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _serverCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL del Servidor RTMP / RTMPS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _platform == StreamPlatform.youtube
                      ? 'Clave de transmisión de YouTube Studio'
                      : _platform == StreamPlatform.facebook
                          ? 'Clave de transmisión de Facebook Live'
                          : 'Clave / Stream Key (opcional si va en la URL)',
                  hintText: 'Pega aquí tu Stream Key',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Calidad: ', style: TextStyle(fontSize: 12.5)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('1.8 Mbps'),
                    selected: _bitrateKbps == 1800,
                    onSelected: (_) => setState(() => _bitrateKbps = 1800),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('2.5 Mbps'),
                    selected: _bitrateKbps == 2500,
                    onSelected: (_) => setState(() => _bitrateKbps = 2500),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('4.0 Mbps'),
                    selected: _bitrateKbps == 4000,
                    onSelected: (_) => setState(() => _bitrateKbps = 4000),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Activar Pantalla Limpia al transmitir',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Muestra el monitor EN VIVO a pantalla completa con botones discretos para cambiar de cámara.',
                  style: TextStyle(fontSize: 11),
                ),
                value: _enterCleanMode,
                onChanged: (v) => setState(() => _enterCleanMode = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          onPressed: _start,
          icon: const Icon(Icons.sensors_rounded),
          label: const Text('INICIAR EN VIVO'),
        ),
      ],
    );
  }
}
