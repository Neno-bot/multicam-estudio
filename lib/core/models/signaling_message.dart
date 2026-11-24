import 'dart:convert';

class SignalingMessage {
  final String type; // register | offer | answer | ice_candidate | tally | error
  final String cameraId;
  final Map<String, dynamic> payload;

  const SignalingMessage({
    required this.type,
    required this.cameraId,
    this.payload = const {},
  });

  String toJsonString() => jsonEncode({
        'type': type,
        'cameraId': cameraId,
        'payload': payload,
      });

  factory SignalingMessage.fromJsonString(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return SignalingMessage(
      type: map['type'] as String,
      cameraId: (map['cameraId'] ?? '') as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
    );
  }
}
