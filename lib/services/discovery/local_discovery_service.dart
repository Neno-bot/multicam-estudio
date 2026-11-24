import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../core/constants/network_constants.dart';

class DiscoveredDirector {
  final String host;
  final int port;
  final String name;

  const DiscoveredDirector({
    required this.host,
    required this.port,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDirector && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

class LocalDiscoveryService {
  // Lado Director (Anunciante)
  BonsoirBroadcast? _mdnsBroadcast;
  RawDatagramSocket? _udpSenderSocket;
  Timer? _udpBroadcastTimer;

  // Lado Cámara (Buscador)
  BonsoirDiscovery? _mdnsDiscovery;
  RawDatagramSocket? _udpListenerSocket;
  StreamSubscription? _mdnsSubscription;

  final _directorFoundController =
      StreamController<DiscoveredDirector>.broadcast();
  Stream<DiscoveredDirector> get onDirectorFound =>
      _directorFoundController.stream;

  /// Obtiene la IP Wi-Fi local actual del dispositivo
  Future<String> getLocalIpAddress() async {
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty) return wifiIp;
    } catch (_) {}

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}

    return '127.0.0.1';
  }

  /// DIRECTOR: Anuncia su presencia vía mDNS + UDP Broadcast
  Future<String> startAdvertisingDirector({
    String directorName = NetworkConstants.mdnsServiceName,
    int signalingPort = NetworkConstants.signalingPort,
  }) async {
    final localIp = await getLocalIpAddress();

    // 1. Anuncio mDNS (Bonsoir)
    try {
      final service = BonsoirService(
        name: directorName,
        type: NetworkConstants.mdnsServiceType,
        port: signalingPort,
      );
      _mdnsBroadcast = BonsoirBroadcast(service: service);
      await _mdnsBroadcast!.ready;
      await _mdnsBroadcast!.start();
    } catch (_) {
      // Si mDNS no está disponible en la red, la baliza UDP sigue operando
    }

    // 2. Baliza UDP Broadcast periódica
    _udpSenderSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udpSenderSocket!.broadcastEnabled = true;

    final payload = utf8.encode(jsonEncode({
      'magic': NetworkConstants.discoveryMagic,
      'name': directorName,
      'host': localIp,
      'port': signalingPort,
    }));

    void sendBeacon() {
      try {
        _udpSenderSocket?.send(
          payload,
          InternetAddress('255.255.255.255'),
          NetworkConstants.udpDiscoveryPort,
        );
      } catch (_) {}
    }

    sendBeacon();
    _udpBroadcastTimer = Timer.periodic(
      NetworkConstants.discoveryBroadcastInterval,
      (_) => sendBeacon(),
    );

    return localIp;
  }

  /// CÁMARA: Escucha anuncios mDNS + paquetes UDP para encontrar al Director
  Future<void> startDiscoveringDirector() async {
    // 1. Escucha mDNS
    try {
      _mdnsDiscovery = BonsoirDiscovery(type: NetworkConstants.mdnsServiceType);
      await _mdnsDiscovery!.ready;
      _mdnsSubscription = _mdnsDiscovery!.eventStream?.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service?.resolve(_mdnsDiscovery!.serviceResolver);
        } else if (event.type ==
            BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final resolved = event.service;
          if (resolved is ResolvedBonsoirService &&
              resolved.host != null &&
              !_directorFoundController.isClosed) {
            _directorFoundController.add(
              DiscoveredDirector(
                host: resolved.host!,
                port: resolved.port,
                name: resolved.name,
              ),
            );
          }
        }
      });
      await _mdnsDiscovery!.start();
    } catch (_) {}

    // 2. Escucha UDP Broadcast
    _udpListenerSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      NetworkConstants.udpDiscoveryPort,
      reuseAddress: true,
    );
    _udpListenerSocket!.broadcastEnabled = true;

    _udpListenerSocket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _udpListenerSocket!.receive();
      if (datagram == null) return;

      try {
        final data =
            jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        if (data['magic'] == NetworkConstants.discoveryMagic &&
            !_directorFoundController.isClosed) {
          _directorFoundController.add(
            DiscoveredDirector(
              host: (data['host'] as String?) ?? datagram.address.address,
              port: (data['port'] as int?) ?? NetworkConstants.signalingPort,
              name: (data['name'] as String?) ?? 'Director',
            ),
          );
        }
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _udpBroadcastTimer?.cancel();
    _udpBroadcastTimer = null;

    _udpSenderSocket?.close();
    _udpSenderSocket = null;

    _udpListenerSocket?.close();
    _udpListenerSocket = null;

    await _mdnsSubscription?.cancel();
    _mdnsSubscription = null;

    await _mdnsBroadcast?.stop();
    _mdnsBroadcast = null;

    await _mdnsDiscovery?.stop();
    _mdnsDiscovery = null;
  }

  Future<void> dispose() async {
    await stop();
    if (!_directorFoundController.isClosed) {
      await _directorFoundController.close();
    }
  }
}
