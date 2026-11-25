import 'package:flutter/material.dart';

enum OverlayMediaFormat {
  png,
  gif,
  webp,
  webm;

  static OverlayMediaFormat fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.webm')) return OverlayMediaFormat.webm;
    if (lower.endsWith('.gif')) return OverlayMediaFormat.gif;
    if (lower.endsWith('.webp')) return OverlayMediaFormat.webp;
    return OverlayMediaFormat.png;
  }

  String get badgeLabel {
    switch (this) {
      case OverlayMediaFormat.png:
        return 'PNG';
      case OverlayMediaFormat.gif:
        return 'GIF';
      case OverlayMediaFormat.webp:
        return 'WEBP';
      case OverlayMediaFormat.webm:
        return 'WEBM';
    }
  }

  bool get isVideo => this == OverlayMediaFormat.webm;
}

enum OverlayPosition {
  fullscreen,
  bottom,
  top;

  String get label {
    switch (this) {
      case OverlayPosition.fullscreen:
        return 'Completa';
      case OverlayPosition.bottom:
        return 'Inferior';
      case OverlayPosition.top:
        return 'Superior';
    }
  }

  Alignment get alignment {
    switch (this) {
      case OverlayPosition.fullscreen:
        return Alignment.center;
      case OverlayPosition.bottom:
        return Alignment.bottomCenter;
      case OverlayPosition.top:
        return Alignment.topCenter;
    }
  }
}

enum WatermarkCorner {
  topRight,
  topLeft,
  bottomRight,
  bottomLeft;

  String get label {
    switch (this) {
      case WatermarkCorner.topRight:
        return 'Sup. Der.';
      case WatermarkCorner.topLeft:
        return 'Sup. Izq.';
      case WatermarkCorner.bottomRight:
        return 'Inf. Der.';
      case WatermarkCorner.bottomLeft:
        return 'Inf. Izq.';
    }
  }
}

/// Plantilla / Cintillo independiente (Nivel Medio — Downstream Keyer).
/// Se superpone sobre la cámara o pauta activa sin interrumpir video ni audio.
class OverlayLayerItem {
  final String id;
  final String name;
  final String filePath;
  final OverlayMediaFormat format;
  final bool isActive;
  final double opacity;
  final OverlayPosition position;

  const OverlayLayerItem({
    required this.id,
    required this.name,
    required this.filePath,
    required this.format,
    this.isActive = false,
    this.opacity = 1.0,
    this.position = OverlayPosition.fullscreen,
  });

  OverlayLayerItem copyWith({
    String? name,
    bool? isActive,
    double? opacity,
    OverlayPosition? position,
  }) {
    return OverlayLayerItem(
      id: id,
      name: name ?? this.name,
      filePath: filePath,
      format: format,
      isActive: isActive ?? this.isActive,
      opacity: opacity ?? this.opacity,
      position: position ?? this.position,
    );
  }
}

/// Slot fijo exclusivo para Marca de Agua / Logo (Nivel Superior).
/// Siempre se dibuja encima de cámaras, pauta y plantillas.
class WatermarkConfig {
  final String? filePath;
  final bool isVisible;
  final double opacity; // 0.15 a 1.0
  final double scale; // 0.08 a 0.35 del ancho del monitor
  final WatermarkCorner corner;

  const WatermarkConfig({
    this.filePath,
    this.isVisible = false,
    this.opacity = 0.9,
    this.scale = 0.18,
    this.corner = WatermarkCorner.topRight,
  });

  bool get hasImage => filePath != null && filePath!.isNotEmpty;

  WatermarkConfig copyWith({
    String? filePath,
    bool? isVisible,
    double? opacity,
    double? scale,
    WatermarkCorner? corner,
    bool clearFile = false,
  }) {
    return WatermarkConfig(
      filePath: clearFile ? null : (filePath ?? this.filePath),
      isVisible: isVisible ?? this.isVisible,
      opacity: opacity ?? this.opacity,
      scale: scale ?? this.scale,
      corner: corner ?? this.corner,
    );
  }
}
