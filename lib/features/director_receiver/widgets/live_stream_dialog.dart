import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Diálogo optimizado para horizontal (teléfono y tablet):
/// - Botón PEGAR de 1 toque (lee el portapapeles sin necesidad de abrir el teclado)
/// - Detecta automáticamente claves de Facebook (FB-...) y URLs rtmps://
/// - Clave visible con interruptor ojo (ver/ocultar) para verificarla al instante
/// - Scroll completo incluso con el teclado abierto (nunca queda tapado el campo)
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
  // Recuerda la última plataforma/clave durante la sesión para no volver a pegarla
  static StreamPlatform _lastPlatform = StreamPlatform.facebook;
  static String _lastServer = AppConstants.facebookRtmpsBase;
  static String _lastKey = '';

  late StreamPlatform _platform;
  late final TextEditingController _serverCtrl;
  late final TextEditingController _keyCtrl;
  int _bitrateKbps = 2500;
  bool _enterCleanMode = false;
  bool _hideKey = false;
  bool _showServerField = false;
  String? _pasteFeedback;

  @override
  void initState() {
    super.initState();
    _platform = _lastPlatform;
    _serverCtrl = TextEditingController(text: _lastServer);
    _keyCtrl = TextEditingController(text: _lastKey);
    _showServerField = _platform == StreamPlatform.custom;
  }

  @override
  void dispose() {
    _lastPlatform = _platform;
    _lastServer = _serverCtrl.text.trim();
    _lastKey = _keyCtrl.text.trim();
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
          _showServerField = false;
          break;
        case StreamPlatform.facebook:
          _serverCtrl.text = AppConstants.facebookRtmpsBase;
          _showServerField = false;
          break;
        case StreamPlatform.custom:
          if (!_serverCtrl.text.startsWith('rtmp')) {
            _serverCtrl.text = 'rtmp://';
          }
          _showServerField = true;
          break;
      }
    });
  }

  /// Pega la clave directo desde el portapapeles en 1 toque (sin abrir teclado)
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (!mounted) return;

    if (raw.isEmpty) {
      setState(() {
        _pasteFeedback = 'El portapapeles está vacío. Copia primero la clave en Facebook o YouTube.';
      });
      return;
    }

    setState(() {
      if (raw.startsWith('rtmp://') || raw.startsWith('rtmps://')) {
        if (raw.contains('facebook.com')) {
          _platform = StreamPlatform.facebook;
          final idx = raw.lastIndexOf('/rtmp/');
          if (idx != -1 && idx + 6 < raw.length) {
            _serverCtrl.text = raw.substring(0, idx + 6);
            _keyCtrl.text = raw.substring(idx + 6);
          } else {
            _serverCtrl.text = raw;
          }
        } else if (raw.contains('youtube.com')) {
          _platform = StreamPlatform.youtube;
          final idx = raw.lastIndexOf('/live2/');
          if (idx != -1 && idx + 7 < raw.length) {
            _serverCtrl.text = raw.substring(0, idx + 7);
            _keyCtrl.text = raw.substring(idx + 7);
          } else {
            _serverCtrl.text = raw;
          }
        } else {
          _platform = StreamPlatform.custom;
          _serverCtrl.text = raw;
          _showServerField = true;
        }
        _pasteFeedback = 'URL y clave detectadas y pegadas correctamente.';
      } else {
        if (raw.toUpperCase().startsWith('FB-')) {
          _platform = StreamPlatform.facebook;
          _serverCtrl.text = AppConstants.facebookRtmpsBase;
        }
        _keyCtrl.text = raw;
        _pasteFeedback = 'Clave pegada correctamente (${raw.length} caracteres).';
      }
    });
  }

  void _start() {
    final server = _serverCtrl.text.trim();
    final key = _keyCtrl.text.trim();

    if (server.isEmpty || (key.isEmpty && _platform != StreamPlatform.custom)) {
      setState(() {
        _pasteFeedback = 'Pega tu Clave de transmisión antes de iniciar.';
      });
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
            Expanded(child: Text('Transmisión EN VIVO activa')),
          ],
        ),
        content: Text(
          widget.currentStatusMessage ??
              'Transmitiendo hacia YouTube / Facebook Live con el micrófono del dispositivo principal.',
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

    final screen = MediaQuery.sizeOf(context);
    final isWide = screen.width >= 600;
    final dialogWidth = isWide ? (screen.width * 0.86).clamp(520.0, 680.0) : 420.0;

    final leftSection = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<StreamPlatform>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
          segments: const [
            ButtonSegment(
              value: StreamPlatform.facebook,
              label: Text('Facebook', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.facebook_rounded, size: 15),
            ),
            ButtonSegment(
              value: StreamPlatform.youtube,
              label: Text('YouTube', style: TextStyle(fontSize: 12)),
              icon: Icon(Icons.play_circle_fill_rounded, size: 15),
            ),
            ButtonSegment(
              value: StreamPlatform.custom,
              label: Text('Otro', style: TextStyle(fontSize: 12)),
            ),
          ],
          selected: {_platform},
          onSelectionChanged: (s) => _selectPlatform(s.first),
        ),
        const SizedBox(height: 10),

        // Fila práctica: Campo de Clave + Botón grande PEGAR (1 toque sin abrir teclado)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _keyCtrl,
                obscureText: _hideKey,
                maxLines: 1,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: _platform == StreamPlatform.facebook
                      ? 'Clave de Facebook Live (FB-...)'
                      : _platform == StreamPlatform.youtube
                          ? 'Clave de YouTube Studio'
                          : 'Clave / Stream Key',
                  hintText: 'Toca PEGAR →',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_keyCtrl.text.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Borrar clave',
                          icon: const Icon(Icons.clear_rounded, size: 17),
                          onPressed: () => setState(() {
                            _keyCtrl.clear();
                            _pasteFeedback = null;
                          }),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: _hideKey ? 'Mostrar clave' : 'Ocultar clave',
                        icon: Icon(
                          _hideKey
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 17,
                        ),
                        onPressed: () => setState(() => _hideKey = !_hideKey),
                      ),
                    ],
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_go_rounded, size: 17),
              label: const Text(
                'PEGAR',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ],
        ),

        if (_pasteFeedback != null) ...[
          const SizedBox(height: 5),
          Text(
            _pasteFeedback!,
            style: TextStyle(
              fontSize: 11,
              color: _pasteFeedback!.contains('correctamente')
                  ? const Color(0xFF4ADE80)
                  : Colors.amberAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Servidor: ${_serverCtrl.text}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              onPressed: () =>
                  setState(() => _showServerField = !_showServerField),
              child: Text(
                _showServerField ? 'Ocultar URL' : 'Editar URL',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        if (_showServerField) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _serverCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'URL del Servidor RTMP / RTMPS',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
            ),
          ),
        ],
      ],
    );

    final rightSection = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Calidad de subida:',
          style: TextStyle(fontSize: 11.5, color: Colors.white70),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: const Text('1.8 Mbps', style: TextStyle(fontSize: 11)),
              selected: _bitrateKbps == 1800,
              onSelected: (_) => setState(() => _bitrateKbps = 1800),
            ),
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: const Text('2.5 Mbps', style: TextStyle(fontSize: 11)),
              selected: _bitrateKbps == 2500,
              onSelected: (_) => setState(() => _bitrateKbps = 2500),
            ),
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: const Text('4.0 Mbps', style: TextStyle(fontSize: 11)),
              selected: _bitrateKbps == 4000,
              onSelected: (_) => setState(() => _bitrateKbps = 4000),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Vista Pantalla Completa (opcional)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Solo se transmite el cuadro rojo EN VIVO (sin botones ni notificaciones).',
            style: TextStyle(fontSize: 10),
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
              icon: const Icon(Icons.sensors_rounded, size: 18),
              label: const Text(
                'INICIAR EN VIVO',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ],
    );

    return Dialog(
      backgroundColor: const Color(0xFF141923),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: screen.height * 0.92,
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
                    Icons.live_tv_rounded,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Transmitir a Facebook / YouTube Live',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
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
              const SizedBox(height: 8),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 56, child: leftSection),
                    const SizedBox(width: 14),
                    Expanded(flex: 44, child: rightSection),
                  ],
                )
              else ...[
                leftSection,
                const SizedBox(height: 10),
                rightSection,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
