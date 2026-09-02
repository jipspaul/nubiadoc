import '../../router/app_router.dart';

/// Résout la route de navigation d'une notification pro (secrétariat) à
/// partir de son `kind` (colonne `notification.kind`, cf. `api/src/notify.rs`).
///
/// Fonction pure, sans dépendance au `BuildContext` : testable seule.
/// Même pattern que `NotificationRouteResolver` d'`app_patient` (#5316) —
/// adapté aux kinds/écrans pro (#6264, dépend du panneau #6263).
class NotificationRouteResolver {
  const NotificationRouteResolver._();

  /// [data] est la charge utile JSON de la notification (ex. `conversation_id`
  /// pour `message_received`). `null` = kind inconnu ou non pertinent pour
  /// cette app : le panneau reste ouvert, aucune navigation (pas de crash).
  static String? resolve({required String? kind, Map<String, dynamic>? data}) {
    switch (kind) {
      case 'appointment_requested':
      case 'callback_requested':
        return AppRouter.agenda;
      case 'message_received':
        final conversationId = data?['conversation_id'] as String?;
        return conversationId != null
            ? '${AppRouter.messages}?conversationId=$conversationId'
            : AppRouter.messages;
      case 'stock':
        return AppRouter.stock;
      default:
        return null;
    }
  }
}
