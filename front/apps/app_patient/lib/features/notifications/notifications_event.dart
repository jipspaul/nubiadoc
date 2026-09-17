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
