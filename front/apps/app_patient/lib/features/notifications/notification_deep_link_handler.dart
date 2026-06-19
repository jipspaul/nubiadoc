import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
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

  static String? _resolveRoute(String? type, String? targetId) {
    if (type == null) return null;
    final id = (targetId != null && targetId.isNotEmpty) ? targetId : null;
    switch (type) {
      case 'appointment':
        return id != null
            ? '${AppRouter.mesRdv}?id=$id'
            : AppRouter.mesRdv;
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
      default:
        return AppRouter.notifications;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
