import 'dart:async';

import 'package:flutter/services.dart';

class GalleryRecordEvent {
  final String event; // started | saved | error
  final String message;

  const GalleryRecordEvent({required this.event, required this.message});
}

/// Puente nativo hacia Android ScreenRecordService (MediaProjection + MediaRecorder + MediaStore)
/// para grabar toda la producción (cámaras + pauta + overlays + marca de agua + micrófono)
/// como un solo MP4 continuo guardado directamente en la Galería (Movies/NenoCam Studio).
class GalleryRecorderService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.nenocam.studio/recorder');
  static const EventChannel _eventChannel =
      EventChannel('com.nenocam.studio/recorder_events');

  Stream<GalleryRecordEvent>? _events;

  Stream<GalleryRecordEvent> get events {
    _events ??= _eventChannel.receiveBroadcastStream().map((dynamic raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      return GalleryRecordEvent(
        event: (map['event'] as String?) ?? 'unknown',
        message: (map['message'] as String?) ?? '',
      );
    });
    return _events!;
  }

  Future<void> startRecording({
    int width = 1280,
    int height = 720,
    int bitrateKbps = 4000,
    bool audioEnabled = true,
  }) async {
    await _methodChannel.invokeMethod<bool>('startRecording', {
      'width': width,
      'height': height,
      'bitrateKbps': bitrateKbps,
      'audioEnabled': audioEnabled,
    });
  }

  Future<void> stopRecording() async {
    await _methodChannel.invokeMethod<bool>('stopRecording');
  }

  Future<bool> isRecording() async {
    final result = await _methodChannel.invokeMethod<bool>('isRecording');
    return result == true;
  }
}
