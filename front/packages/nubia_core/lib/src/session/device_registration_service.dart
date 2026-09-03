import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';

/// Registers this device's FCM push token with the backend after login, and
/// keeps it fresh via [FirebaseMessaging.onTokenRefresh].
///
/// Mobile only (guard par [defaultTargetPlatform]) : le web garde
/// l'in-app seul, les service workers y sont désactivés par design. Fire-and-
/// forget — les erreurs (Firebase non configuré nativement en dev/CI, réseau
/// indisponible, …) sont silencieuses pour ne jamais bloquer le login.
///
/// Le token enregistré est persisté via [TokenStorage.saveFcmToken] : c'est
/// lui que `AuthRepositoryImpl.logout()` relit pour désenregistrer le device
/// (`DELETE /v1/devices/:token`) à la déconnexion.
class DeviceRegistrationService {
  DeviceRegistrationService(ApiClient client, this._tokenStorage)
      : _dio = client.dio;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  StreamSubscription<String>? _refreshSubscription;

  Future<void> registerOnLogin(String app) async {
    if (!_isMobile) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
      await _refreshSubscription?.cancel();
      _refreshSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen(_register);
    } catch (_) {
      // Firebase non configuré sur cette plateforme (config native absente
      // en dev/CI notamment) : jamais bloquer le login pour ça.
    }
  }

  Future<void> _register(String token) async {
    try {
      await _dio.post<void>(
        '/devices',
        data: {'fcm_token': token, 'platform': _platform()},
      );
      await _tokenStorage.saveFcmToken(token);
    } catch (_) {
      // Erreur réseau : le prochain login/refresh retentera.
    }
  }

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  String _platform() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}
