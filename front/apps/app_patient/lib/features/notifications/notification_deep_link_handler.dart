import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'notification_route_resolver.dart';

/// Handles push notification taps and translates them to go_router navigations.
///
/// Payload contract: `{ "type": "<notification_type>", "target_id": "<id>" }`.
/// Supports both terminated-state (getInitialMessage) and background-state
/// (onMessageOpenedApp) tap scenarios.
class NotificationDeepLinkHandler {
  final GoRouter _router;
  StreamSubscription<RemoteMessage>? _subscription;

  NotificationDeepLinkHandler(this._router);

  void init() {
    unawaited(_setup());
  }

  Future<void> _setup() async {
    try {
      // Terminated state: app cold-launched via notification tap.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _navigate(initial);

      // Background state: app brought to foreground via notification tap.
      _subscription = FirebaseMessaging.onMessageOpenedApp.listen(_navigate);
    } catch (_) {
      // Firebase not initialised (missing native config in dev/CI).
    }
  }

  void _navigate(RemoteMessage message) {
    final route = NotificationRouteResolver.resolve(
      type: message.data['type'] as String?,
      targetId: message.data['target_id'] as String?,
    );
    if (route != null) _router.go(route);
  }

  /// Hook de test : la résolution des routes est pure.
  @visibleForTesting
  static String? resolveRouteForTest(String? type, String? targetId) =>
      NotificationRouteResolver.resolve(type: type, targetId: targetId);

  void dispose() {
    _subscription?.cancel();
  }
}
