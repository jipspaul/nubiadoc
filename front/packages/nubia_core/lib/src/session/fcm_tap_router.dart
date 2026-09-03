import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Wires push notification taps to `go_router` navigation, resolving the
/// target route with an app-supplied [resolve] callback (each app has its
/// own `NotificationRouteResolver`, cf. #6280).
///
/// Supports both terminated-state (`getInitialMessage`) and background-state
/// (`onMessageOpenedApp`) tap scenarios. Mobile only — never throws if
/// Firebase isn't configured on this platform (web, or native config absent
/// in dev/CI) : same pattern that `DeviceRegistrationService` uses.
class FcmTapRouter {
  FcmTapRouter(this._router, this._resolve);

  final GoRouter _router;
  final String? Function(RemoteMessage message) _resolve;
  StreamSubscription<RemoteMessage>? _subscription;

  void init() {
    if (!_isMobile) return;
    unawaited(_setup());
  }

  Future<void> _setup() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _navigate(initial);
      _subscription = FirebaseMessaging.onMessageOpenedApp.listen(_navigate);
    } catch (_) {
      // Firebase non configuré sur cette plateforme : pas de crash.
    }
  }

  void _navigate(RemoteMessage message) {
    final route = _resolve(message);
    if (route != null) _router.go(route);
  }

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  void dispose() {
    _subscription?.cancel();
  }
}
