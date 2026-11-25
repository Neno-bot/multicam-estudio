import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String releaseName;
  final String downloadUrl;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseName,
    required this.downloadUrl,
    required this.hasUpdate,
  });
}

class UpdateCheckService {
  /// Consulta el último release de GitHub y compara la versión con AppConstants.appVersion
  Future<AppUpdateInfo?> checkForUpdate() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(
        Uri.parse(AppConstants.latestReleaseApiUrl),
      );
      req.headers.set(HttpHeaders.userAgentHeader, 'NenoCam-Studio-App');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final releaseName = (json['name'] as String?) ?? '';
      final assets = (json['assets'] as List?) ?? const [];

      final downloadUrl = selectBestArm64AssetUrl(assets);

      final extracted = extractVersion(releaseName) ?? AppConstants.appVersion;
      final isNewer = isVersionNewer(extracted, AppConstants.appVersion);

      return AppUpdateInfo(
        latestVersion: extracted,
        releaseName: releaseName,
        downloadUrl: downloadUrl,
        hasUpdate: isNewer,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Prioriza siempre el APK arm64 de NenoCam Studio sobre archivos heredados
  static String selectBestArm64AssetUrl(List<dynamic> assets) {
    String? fallbackArm64;
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = ((asset['name'] as String?) ?? '').toLowerCase();
        final url = asset['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;
        if (name.contains('arm64') && name.endsWith('.apk')) {
          if (name.contains('nenocam')) {
            return url;
          }
          fallbackArm64 ??= url;
        }
      }
    }
    return fallbackArm64 ?? AppConstants.directArm64ApkUrl;
  }

  /// Extrae un número de versión tipo v1.3 o 1.3.0 desde el título del release
  static String? extractVersion(String text) {
    final match = RegExp(r'v?(\d+\.\d+(?:\.\d+)?)').firstMatch(text);
    return match?.group(1);
  }

  static bool isVersionNewer(String remote, String current) {
    final rParts = _parseParts(remote);
    final cParts = _parseParts(current);
    for (int i = 0; i < 3; i++) {
      if (rParts[i] > cParts[i]) return true;
      if (rParts[i] < cParts[i]) return false;
    }
    return false;
  }

  static List<int> _parseParts(String version) {
    final raw = version.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (raw.length < 3) {
      raw.add(0);
    }
    return raw.take(3).toList();
  }
}
