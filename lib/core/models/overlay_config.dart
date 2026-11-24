enum TransitionMode {
  cut,
  fade,
}

class OverlayConfig {
  final bool isVisible;
  final String title;
  final String subtitle;

  const OverlayConfig({
    this.isVisible = false,
    this.title = 'EN DIRECTO',
    this.subtitle = 'MultiCam Studio',
  });

  OverlayConfig copyWith({
    bool? isVisible,
    String? title,
    String? subtitle,
  }) {
    return OverlayConfig(
      isVisible: isVisible ?? this.isVisible,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
    );
  }
}
