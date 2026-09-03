import '../../router/app_router.dart';

/// Résout la route de navigation d'une notification pro (pharmacie) à
/// partir de son `kind` (colonne `notification.kind`, cf. `api/src/notify.rs`
/// — ex. `order_received` déjà émis par `prescription_send.rs`).
///
/// Fonction pure, sans dépendance au `BuildContext` : testable seule.
/// Même pattern que `NotificationRouteResolver` d'`app_patient` (#5316) —
/// adapté aux kinds/écrans pro (#6264, dépend du panneau #6263).
class NotificationRouteResolver {
  const NotificationRouteResolver._();

  /// `null` = kind inconnu ou non pertinent pour cette app : le panneau
  /// reste ouvert, aucune navigation (pas de crash).
  static String? resolve({required String? kind, Map<String, dynamic>? data}) {
    switch (kind) {
      case 'order_received':
      case 'order_status_changed':
        return AppRouter.orders;
      case 'stock_request_received':
        return AppRouter.stock;
      case 'pharmacy_quote_sent':
      case 'pharmacy_quote_decided':
        return AppRouter.devis;
      case 'message_received':
        return AppRouter.messages;
      default:
        return null;
    }
  }
}
