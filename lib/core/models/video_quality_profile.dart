enum VideoQualityProfile {
  sd480p(
    id: '480p',
    label: '480p30',
    width: 854,
    height: 480,
    frameRate: 30,
    maxBitrateKbps: 1200,
  ),
  hd720p(
    id: '720p',
    label: '720p30',
    width: 1280,
    height: 720,
    frameRate: 30,
    maxBitrateKbps: 2800,
  ),
  fhd1080p(
    id: '1080p',
    label: '1080p30',
    width: 1920,
    height: 1080,
    frameRate: 30,
    maxBitrateKbps: 5500,
  );

  final String id;
  final String label;
  final int width;
  final int height;
  final int frameRate;
  final int maxBitrateKbps;

  const VideoQualityProfile({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.maxBitrateKbps,
  });

  static VideoQualityProfile fromId(String? id) {
    return VideoQualityProfile.values.firstWhere(
      (p) => p.id == id,
      orElse: () => VideoQualityProfile.hd720p,
    );
  }
}
