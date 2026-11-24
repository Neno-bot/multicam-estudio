import 'dart:async';

import 'package:flutter/services.dart';

class RtmpStreamEvent {
  final String event; // connecting | connected | error | disconnected | bitrate
  final String message;

  const RtmpStreamEvent({required this.event, required this.message});
}

/// Puente nativo hacia Android RtmpStreamService (RootEncoder + MediaProjection)
/// para transmitir hacia YouTube Live (RTMP) y Facebook Live (RTMPS).
class RtmpStreamService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.nenocam.studio/rtmp');
  static const EventChannel _eventChannel =
      EventChannel('com.nenocam.studio/rtmp_events');

  Stream<RtmpStreamEvent>? _events;

  Stream<RtmpStreamEvent> get events {
    _events ??= _eventChannel.receiveBroadcastStream().map((dynamic raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      return RtmpStreamEvent(
        event: (map['event'] as String?) ?? 'unknown',
        message: (map['message'] as String?) ?? '',
      );
    });
    return _events!;
  }

  Future<void> startStream({
    required String rtmpUrl,
    int bitrateKbps = 2500,
    bool audioEnabled = true,
  }) async {
    await _methodChannel.invokeMethod<bool>('startStream', {
      'url': rtmpUrl,
      'bitrateKbps': bitrateKbps,
      'audioEnabled': audioEnabled,
    });
  }

  Future<void> stopStream() async {
    await _methodChannel.invokeMethod<bool>('stopStream');
  }

  Future<bool> isStreaming() async {
    final result = await _methodChannel.invokeMethod<bool>('isStreaming');
    return result == true;
  }
}
