import '../../router/app_router.dart';

/// Résout la route de navigation d'une notification, qu'elle provienne d'un
/// push FCM (`type` + `targetId`) ou de l'inbox (`deepLink` API).
///
/// Fonction pure, sans dépendance à Firebase ni au `BuildContext` : testable
/// depuis n'importe quel contexte. Unifie ce qui était auparavant deux
/// résolveurs divergents (`NotificationDeepLinkHandler._resolveRoute` et
/// `_NotificationTile._resolveDeepLink`).
class NotificationRouteResolver {
  const NotificationRouteResolver._();

  static String? resolve({String? type, String? targetId, String? deepLink}) {
    if (type != null) {
      return _resolveFromType(type, targetId);
    }
    if (deepLink != null && deepLink.isNotEmpty) {
      return _resolveFromDeepLink(deepLink);
    }
    return null;
  }

  static String _resolveFromType(String type, String? targetId) {
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

  /// Traduit un `deep_link` API en route app. `/appointments/<id>` n'a pas de
  /// route dédiée côté patient (`/appointments` sert au booking, sans `:id`) ;
  /// on réutilise la convention `mesRdv?id=` déjà en place pour les push FCM.
  /// `/messages/<id>` (émis par `derive_deep_link` côté API pour
  /// `message_received`, #6482) ne correspond à aucune route déclarée : la
  /// conversation vit sous `/messaging/:id` (`app_router.dart`) ; on
  /// retraduit donc le préfixe. Les autres deep_links (ex.
  /// `/pharmacy/orders/<id>`) correspondent déjà à une route existante.
  static String _resolveFromDeepLink(String deepLink) {
    final appointmentMatch = RegExp(
      r'^/appointments/(.+)$',
    ).firstMatch(deepLink);
    if (appointmentMatch != null) {
      return '${AppRouter.mesRdv}?id=${appointmentMatch.group(1)}';
    }
    final messageMatch = RegExp(r'^/messages(?:/(.+))?$').firstMatch(deepLink);
    if (messageMatch != null) {
      final id = messageMatch.group(1);
      return id != null ? '${AppRouter.messaging}/$id' : AppRouter.messaging;
    }
    return deepLink;
  }
}
