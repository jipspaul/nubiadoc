import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';

/// Registers this device's FCM push token with the backend after login.
///
/// Fire-and-forget: errors are silenced so login is never blocked.
class DeviceRegistrationService {
  DeviceRegistrationService(ApiClient client) : _dio = client.dio;

  final Dio _dio;

  Future<void> registerOnLogin(String app) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _dio.post<void>(
        '/devices',
        data: {'token': token, 'platform': _platform(), 'app': app},
      );
    } catch (_) {
      // Don't block login on FCM/network errors.
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'android';
    }
  }
}
