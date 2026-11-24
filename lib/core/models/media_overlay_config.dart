enum ImageOverlayPlacement {
  topRightLogo,
  topLeftLogo,
  fullscreenSlide,
}

class ImageOverlayConfig {
  final String? filePath;
  final bool isVisible;
  final ImageOverlayPlacement placement;
  final double sizeFactor; // 0.12 a 0.35 para logos

  const ImageOverlayConfig({
    this.filePath,
    this.isVisible = false,
    this.placement = ImageOverlayPlacement.topRightLogo,
    this.sizeFactor = 0.2,
  });

  bool get hasImage => filePath != null && filePath!.isNotEmpty;

  ImageOverlayConfig copyWith({
    String? filePath,
    bool? isVisible,
    ImageOverlayPlacement? placement,
    double? sizeFactor,
    bool clearFile = false,
  }) {
    return ImageOverlayConfig(
      filePath: clearFile ? null : (filePath ?? this.filePath),
      isVisible: isVisible ?? this.isVisible,
      placement: placement ?? this.placement,
      sizeFactor: sizeFactor ?? this.sizeFactor,
    );
  }
}

enum AudioMixMode {
  /// Solo la Tablet (Director) usa micrófono; todos los teléfonos emisores van silenciados.
  tabletOnly,

  /// Audio Follows Video: solo suena el teléfono que está EN VIVO.
  afv,

  /// Mezcla manual de los teléfonos que no estén silenciados.
  mix,
}

enum StreamPlatform {
  youtube,
  facebook,
  custom,
}

enum RtmpStreamStatus {
  idle,
  connecting,
  live,
  error,
}
