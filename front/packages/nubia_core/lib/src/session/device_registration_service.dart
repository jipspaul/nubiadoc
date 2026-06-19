import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers the FCM push token with the backend after a successful login.
///
/// Fire-and-forget: errors are silenced so they never block the login flow.
class DeviceRegistrationService {
  DeviceRegistrationService(this._dio);

  final Dio _dio;

  Future<void> registerOnLogin(String app) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      final platform = _platformName();
      if (platform == null) return;

      await _dio.post<void>(
        '/v1/devices',
        data: {'token': token, 'platform': platform, 'app': app},
      );
    } catch (_) {
      // Intentionally silent — device registration must not block login.
    }
  }

  String? _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }
}
