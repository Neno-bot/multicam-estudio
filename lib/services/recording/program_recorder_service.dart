import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

/// Servicio de grabación local del Monitor Principal (PGM) en formato MP4.
/// Si el Director cambia de cámara durante la grabación, guarda el segmento
/// actual e inicia automáticamente el siguiente para evitar corrupción de pista.
class ProgramRecorderService {
  MediaRecorder? _recorder;
  bool _isRecording = false;
  int _segmentCounter = 0;
  String? _sessionPrefix;
  final List<String> _savedFiles = [];

  bool get isRecording => _isRecording;
  List<String> get savedFiles => List.unmodifiable(_savedFiles);

  Future<String> _buildOutputPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/multicam_recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    _segmentCounter++;
    return '${recordingsDir.path}/${_sessionPrefix}_part$_segmentCounter.mp4';
  }

  /// Inicia una nueva sesión de grabación usando la pista de video del stream PGM
  Future<void> startSession(MediaStream activeStream) async {
    if (_isRecording) return;
    final videoTracks = activeStream.getVideoTracks();
    if (videoTracks.isEmpty) {
      throw StateError('No hay pista de video activa para grabar.');
    }

    final now = DateTime.now();
    _sessionPrefix =
        'REC_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    _segmentCounter = 0;
    _savedFiles.clear();

    await _startSegment(videoTracks.first);
    _isRecording = true;
  }

  /// Rota limpiamente al nuevo stream si se cambia la cámara EN VIVO durante REC
  Future<void> switchRecordedStream(MediaStream newStream) async {
    if (!_isRecording) return;
    final videoTracks = newStream.getVideoTracks();
    if (videoTracks.isEmpty) return;

    await _stopCurrentSegment();
    await _startSegment(videoTracks.first);
  }

  Future<void> _startSegment(MediaStreamTrack videoTrack) async {
    final path = await _buildOutputPath();
    _recorder = MediaRecorder();
    await _recorder!.start(
      path,
      videoTrack: videoTrack,
      audioChannel: RecorderAudioChannel.INPUT,
    );
    _savedFiles.add(path);
  }

  Future<void> _stopCurrentSegment() async {
    try {
      await _recorder?.stop();
    } catch (_) {}
    _recorder = null;
  }

  /// Detiene la grabación y devuelve la lista de clips guardados
  Future<List<String>> stopSession() async {
    if (!_isRecording) return const [];
    _isRecording = false;
    await _stopCurrentSegment();
    return List.unmodifiable(_savedFiles);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> dispose() async {
    if (_isRecording) {
      await stopSession();
    }
  }
}
