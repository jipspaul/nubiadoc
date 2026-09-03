import 'dart:async';

import 'package:nubia_domain/nubia_domain.dart';

import 'ws_client.dart';

/// Implémentation WebSocket du [NotificationEventsPort].
///
/// Quoi : s'abonne au canal `notifications` de `/v1/ws` (canal personnel,
/// dérivé du JWT côté serveur) et mappe chaque enveloppe
/// `{channel:"notifications", event:"notification_created", data:{…}}` en
/// [IncomingNotification].
/// Quand : dès le premier écouteur ; interim « app vivante » avant FCM/APNs.
/// Pourquoi cette approche : même pattern que [WsPharmacyOrderEvents] —
/// le REST reste la source de vérité, le WS n'est qu'un nudge enrichi.
/// Modes d'échec : best-effort — pas de token / connexion impossible ⇒ flux
/// muet (le polling 60 s du badge reste le filet), reconnexion+re-subscribe
/// assurés par [WsClient].
class WsNotificationEvents implements NotificationEventsPort {
  WsNotificationEvents({required WsClient client}) : _client = client;

  final WsClient _client;
  StreamController<IncomingNotification>? _controller;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  Stream<IncomingNotification> watch() {
    final existing = _controller;
    if (existing != null) return existing.stream;

    final controller = StreamController<IncomingNotification>.broadcast(
      onListen: () async {
        try {
          await _client.subscribe('notifications');
          _subscription = _client.events.listen((envelope) {
            if (envelope['channel'] != 'notifications') return;
            final data = envelope['data'];
            if (data is! Map<String, dynamic>) return;
            final id = data['id'];
            final kind = data['kind'];
            final title = data['title'];
            if (id is! String || kind is! String || title is! String) return;
            final payload = data['data'];
            _controller?.add(IncomingNotification(
              id: id,
              kind: kind,
              title: title,
              data: payload is Map<String, dynamic> ? payload : const {},
            ));
          });
        } catch (_) {
          // Best-effort : sans WS le flux reste simplement muet.
        }
      },
    );
    _controller = controller;
    return controller.stream;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller?.close();
    _controller = null;
    _client.dispose();
  }
}
