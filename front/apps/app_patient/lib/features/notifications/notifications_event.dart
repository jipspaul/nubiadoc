import 'package:equatable/equatable.dart';

sealed class NotificationsEvent extends Equatable {
  const NotificationsEvent();

  @override
  List<Object?> get props => [];
}

final class NotificationsLoadRequested extends NotificationsEvent {
  const NotificationsLoadRequested();
}

/// Charge uniquement `page.unread_count` (#6279), pas la liste paginée —
/// pour l'accueil, qui n'a besoin que du booléen « pastille sur la cloche »
/// (#7102).
final class NotificationsUnreadCountRequested extends NotificationsEvent {
  const NotificationsUnreadCountRequested();
}

final class NotificationMarkReadRequested extends NotificationsEvent {
  final String notificationId;

  const NotificationMarkReadRequested(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

final class NotificationMarkAllReadRequested extends NotificationsEvent {
  const NotificationMarkAllReadRequested();
}

/// Défilement proche du bas de la liste (#8323) : charge la page suivante
/// via `page.next_cursor` plutôt que tout charger avant le premier rendu —
/// même correctif que `DocumentsLoadMoreRequested` pour #8297.
final class NotificationsLoadMoreRequested extends NotificationsEvent {
  const NotificationsLoadMoreRequested();
}
