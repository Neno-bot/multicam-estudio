enum SignalHealth {
  good,
  fair,
  poor,
}

class StreamStats {
  final int width;
  final int height;
  final double fps;
  final double bitrateKbps;
  final double rttMs;
  final int packetsLost;

  const StreamStats({
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.bitrateKbps = 0,
    this.rttMs = 0,
    this.packetsLost = 0,
  });

  SignalHealth get health {
    if (rttMs > 180 || (fps > 0 && fps < 15)) return SignalHealth.poor;
    if (rttMs > 80 || (fps > 0 && fps < 24)) return SignalHealth.fair;
    return SignalHealth.good;
  }

  String get resolutionLabel => height > 0 ? '${height}p' : '--';

  String get bitrateLabel {
    if (bitrateKbps >= 1000) {
      return '${(bitrateKbps / 1000).toStringAsFixed(1)} Mbps';
    }
    return '${bitrateKbps.round()} kbps';
  }

  String get compactSummary {
    final fpsText = '${fps.round()}fps';
    final rttText = rttMs > 0 ? '${rttMs.round()}ms' : '--';
    return '$resolutionLabel • $fpsText • $bitrateLabel • $rttText';
  }
}
