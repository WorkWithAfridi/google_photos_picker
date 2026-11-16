import 'package:flutter/services.dart';

final class GooglePhotosPlatform {
  GooglePhotosPlatform._();

  static const MethodChannel _channel = MethodChannel(
    'google_photos_picker/android',
  );

  static Future<bool> returnToApp() async {
    return await _channel.invokeMethod<bool>('returnToApp') ?? false;
  }

  static Future<void> startSessionMonitor({
    required String sessionId,
    required Map<String, String> headers,
    required Duration pollInterval,
    required Duration timeout,
  }) {
    return _channel.invokeMethod<void>('startSessionMonitor', <String, Object>{
      'sessionId': sessionId,
      'headers': headers,
      'pollIntervalMillis': pollInterval.inMilliseconds,
      'timeoutMillis': timeout.inMilliseconds,
    });
  }

  static Future<void> stopSessionMonitor() {
    return _channel.invokeMethod<void>('stopSessionMonitor');
  }
}
