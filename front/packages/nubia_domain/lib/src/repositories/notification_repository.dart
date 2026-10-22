import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/app_notification.dart';
import 'package:nubia_domain/src/entities/notification_preferences.dart';

/// Une page unique de notifications (#8323) : [nextCursor] permet de
/// charger la suivante à la demande plutôt que de suivre les curseurs
/// jusqu'à épuisement avant le premier rendu — même doctrine que
/// `PagedDocuments` (#8279/#8297). [total] (`page.total`, #8342) est le
/// volume complet de la boîte correspondant au filtre demandé,
/// indépendamment du nombre de notifications déjà chargées.
typedef PagedNotifications = ({
  List<AppNotification> notifications,
  String? nextCursor,
  int? total,
});

abstract class NotificationRepository {
  /// Returns notifications sorted by [AppNotification.createdAt] descending.
  ///
  /// [unreadOnly] maps to `GET /v1/notifications?unread_only=true` — used by
  /// the pro shell's bell badge (#6263) to poll the unread count without
  /// fetching the (heavier) full list.
  Future<Either<Failure, List<AppNotification>>> getNotifications({
    bool unreadOnly = false,
  });

  /// Charge une page unique de notifications (#8323) : [cursor] (issu d'un
  /// appel précédent) enchaîne sur `page.next_cursor` au lieu de paginer
  /// jusqu'à épuisement avant de rendre la main — l'inbox patient suivait
  /// jusque-là le même chemin que [getNotifications] (37 requêtes
  /// séquentielles / 3,1 s de squelettes avant la première notification,
  /// cf. #8323).
  ///
  /// [type] : restreint `data` ET [PagedNotifications.total] à une famille
  /// ([NotificationType.appointment]/[document]/[payment]) — #8357 : la puce
  /// de facette qui annonce ce total doit ouvrir la MÊME liste, pas le
  /// filtre côté client de la seule page déjà chargée (#8323).
  Future<Either<Failure, PagedNotifications>> getPage({
    int limit = 20,
    String? cursor,
    bool unreadOnly = false,
    NotificationType? type,
  });

  /// Returns the total count of unread notifications for the token holder —
  /// independent of any page size, unlike deriving it from [getNotifications]'s
  /// result length (#6279).
  Future<Either<Failure, int>> getUnreadCount();

  /// Comptes par famille ([NotificationType.appointment]/[document]/
  /// [payment]) sur la boîte ENTIÈRE, à coût borné (une requête par
  /// famille, `limit: 1`) — #8342 : les puces de facette de l'écran
  /// Notifications ne doivent pas dépendre des notifications déjà chargées
  /// en mémoire (une page, #8323), mais du volume réel par famille côté
  /// serveur.
  Future<Either<Failure, Map<NotificationType, int>>> typeCounts();

  /// Marks a single notification as read.
  Future<Either<Failure, void>> markRead(String notificationId);

  /// Marks all notifications as read.
  Future<Either<Failure, void>> markAllRead();

  /// Registers the device with the backend via `POST /v1/devices`.
  Future<Either<Failure, void>> registerDevice({
    required String fcmToken,
    required String platform,
  });

  /// Deregisters the device FCM token on the backend (called on logout).
  Future<Either<Failure, void>> unregisterFcmToken(String token);

  /// Returns the user's notification opt-in preferences.
  Future<Either<Failure, NotificationPreferences>> getPreferences();

  /// Persists updated notification preferences.
  Future<Either<Failure, void>> updatePreferences(
    NotificationPreferences preferences,
  );
}
