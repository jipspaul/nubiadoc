import '../../router/app_router.dart';

/// Résout la route de navigation d'une notification pro (praticien) à
/// partir de son `kind` (colonne `notification.kind`, cf. `api/src/notify.rs`).
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
      case 'waiting_room_called':
        return AppRouter.waitingRoom;
      case 'quote_signed':
        return AppRouter.devis;
      case 'lab_work_returned':
        return AppRouter.labWorkOrders;
      default:
        return null;
    }
  }
}
