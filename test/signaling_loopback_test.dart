import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multicam_studio/core/models/signaling_message.dart';
import 'package:multicam_studio/services/signaling/camera_signaling_client.dart';
import 'package:multicam_studio/services/signaling/director_signaling_server.dart';

void main() {
  group('Señalización WebSocket local (Director <-> Cámaras)', () {
    late DirectorSignalingServer server;
    late CameraSignalingClient cam1;
    late CameraSignalingClient cam2;
    const testPort = 18765;

    setUp(() async {
      server = DirectorSignalingServer();
      cam1 = CameraSignalingClient();
      cam2 = CameraSignalingClient();
      await server.start(port: testPort);
    });

    tearDown(() async {
      await cam1.disconnect();
      await cam2.disconnect();
      await server.stop();
    });

    test('registra cámaras, distribuye Tally dual (PGM/PVW) y comandos remotos',
        () async {
      final registeredIds = <String>[];
      final registerDone = Completer<void>();

      server.onMessage = (msg) {
        if (msg.type == 'register') {
          registeredIds.add(msg.cameraId);
          if (registeredIds.length == 2 && !registerDone.isCompleted) {
            registerDone.complete();
          }
        }
      };

      final cam1Messages = <SignalingMessage>[];
      final cam2Messages = <SignalingMessage>[];
      final tallyReceived = Completer<void>();
      final commandReceived = Completer<SignalingMessage>();

      cam1.onMessage = (msg) {
        cam1Messages.add(msg);
        if (msg.type == 'command' && !commandReceived.isCompleted) {
          commandReceived.complete(msg);
        }
      };
      cam2.onMessage = (msg) {
        cam2Messages.add(msg);
        if (msg.type == 'tally' && !tallyReceived.isCompleted) {
          tallyReceived.complete();
        }
      };

      await cam1.connect('127.0.0.1', testPort);
      await cam2.connect('127.0.0.1', testPort);

      cam1.send(
        const SignalingMessage(
          type: 'register',
          cameraId: 'cam-1',
          payload: {'name': 'Cámara 1'},
        ),
      );
      cam2.send(
        const SignalingMessage(
          type: 'register',
          cameraId: 'cam-2',
          payload: {'name': 'Cámara 2'},
        ),
      );

      await registerDone.future.timeout(const Duration(seconds: 3));
      expect(registeredIds, containsAll(['cam-1', 'cam-2']));

      // Enviar Tally dual: cam-1 EN VIVO (rojo), cam-2 PREVIO (verde)
      server.broadcastTally('cam-1', previewCameraId: 'cam-2');
      await tallyReceived.future.timeout(const Duration(seconds: 3));
      await Future.delayed(const Duration(milliseconds: 80));

      final cam1Tally = cam1Messages.firstWhere((m) => m.type == 'tally');
      final cam2Tally = cam2Messages.firstWhere((m) => m.type == 'tally');

      expect(cam1Tally.payload['state'], 'live');
      expect(cam1Tally.payload['isLive'], true);
      expect(cam2Tally.payload['state'], 'preview');
      expect(cam2Tally.payload['isPreview'], true);

      // Enviar comando remoto de calidad a cam-1
      server.sendRemoteCommand(
        'cam-1',
        'set_quality',
        params: {'quality': '1080p'},
      );
      final cmd =
          await commandReceived.future.timeout(const Duration(seconds: 3));
      expect(cmd.payload['action'], 'set_quality');
      expect(cmd.payload['quality'], '1080p');
    });
  });
}
