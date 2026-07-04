import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';

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
    final route = _resolveRoute(
      message.data['type'] as String?,
      message.data['target_id'] as String?,
    );
    if (route != null) _router.go(route);
  }

  /// Hook de test : la résolution des routes est pure.
  @visibleForTesting
  static String? resolveRouteForTest(String? type, String? targetId) =>
      _resolveRoute(type, targetId);

  static String? _resolveRoute(String? type, String? targetId) {
    if (type == null) return null;
    final id = (targetId != null && targetId.isNotEmpty) ? targetId : null;
    switch (type) {
      case 'appointment':
        return id != null ? '${AppRouter.mesRdv}?id=$id' : AppRouter.mesRdv;
      case 'message':
        return id != null
            ? '${AppRouter.messaging}?conversationId=$id'
            : AppRouter.messaging;
      case 'document':
        return id != null
            ? '${AppRouter.documents}?id=$id'
            : AppRouter.documents;
      case 'payment':
        return id != null
            ? '${AppRouter.financial}?id=$id'
            : AppRouter.financial;
      // Commandes click-and-collect (kinds order_received /
      // order_status_changed, data {order_id}) — lot F8.
      case 'order_received':
      case 'order_status_changed':
      case 'pharmacy_order_preparing':
      case 'pharmacy_order_ready':
      case 'pharmacy_order_picked_up':
        return id != null ? '/pharmacy/orders/$id' : '/pharmacy/orders';
      default:
        return AppRouter.notifications;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
