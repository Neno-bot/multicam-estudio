import 'media_overlay_config.dart';

enum MediaCueType {
  image,
  video,
}

/// Elemento pautado en la Bandeja Switcher (Imagen o Video listo para salir al aire en 1 toque)
class MediaCueItem {
  final String id;
  final String label;
  final String filePath;
  final MediaCueType type;
  final ImageOverlayPlacement imagePlacement;

  const MediaCueItem({
    required this.id,
    required this.label,
    required this.filePath,
    required this.type,
    this.imagePlacement = ImageOverlayPlacement.fullscreenSlide,
  });

  bool get isCornerLogo =>
      type == MediaCueType.image &&
      imagePlacement != ImageOverlayPlacement.fullscreenSlide;

  MediaCueItem copyWith({
    String? label,
    ImageOverlayPlacement? imagePlacement,
  }) {
    return MediaCueItem(
      id: id,
      label: label ?? this.label,
      filePath: filePath,
      type: type,
      imagePlacement: imagePlacement ?? this.imagePlacement,
    );
  }
}
