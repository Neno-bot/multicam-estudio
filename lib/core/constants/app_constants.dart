class AppConstants {
  AppConstants._();

  static const String appName = 'NenoCam Studio';
  static const String appVersion = '1.2.0';
  static const String githubRepo = 'Neno-bot/multicam-estudio';

  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  static const String directArm64ApkUrl =
      'https://github.com/$githubRepo/releases/download/latest-android-test/NenoCam-Studio-arm64.apk';

  static const String youtubeRtmpBase = 'rtmp://a.rtmp.youtube.com/live2/';
  static const String facebookRtmpsBase =
      'rtmps://live-api-s.facebook.com:443/rtmp/';
}
