class NetworkConstants {
  NetworkConstants._();

  /// Tipo de servicio mDNS / Bonjour
  static const String mdnsServiceType = '_multicam._tcp';
  static const String mdnsServiceName = 'MultiCam-Director';

  /// Puerto UDP para baliza de descubrimiento rápido en LAN
  static const int udpDiscoveryPort = 45454;

  /// Puerto del servidor WebSocket embebido en la Tablet Director
  static const int signalingPort = 8765;

  /// Intervalo de anuncio UDP del Director
  static const Duration discoveryBroadcastInterval =
      Duration(milliseconds: 1500);

  /// Máximo de cámaras simultáneas en Fase 1
  static const int maxConnectedCameras = 4;

  /// Identificador de protocolo UDP
  static const String discoveryMagic = 'MULTICAM_DIRECTOR_V1';
}
