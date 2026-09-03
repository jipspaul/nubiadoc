import '../../router/app_router.dart';

/// Résout la route de navigation d'une notification infirmière à partir de
/// son `kind` (colonne `notification.kind`, cf. `api/src/notify.rs`).
///
/// Fonction pure, sans dépendance au `BuildContext` : testable seule. Même
/// pattern que `NotificationRouteResolver` d'`app_practicien`/`app_secretariat`/
/// `app_pharmacie` (#6280) — adapté au seul kind émis à l'infirmière
/// aujourd'hui, `visit_offer` (cf. `NurseNotificationsPanel`, qui bascule
/// systématiquement sur l'onglet Offres pour ce kind).
class NotificationRouteResolver {
  const NotificationRouteResolver._();

  /// `null` = kind inconnu ou non pertinent pour cette app : aucune
  /// navigation (pas de crash).
  static String? resolve({required String? kind, Map<String, dynamic>? data}) {
    switch (kind) {
      case 'visit_offer':
        return AppRouter.home;
      default:
        return null;
    }
  }
}
