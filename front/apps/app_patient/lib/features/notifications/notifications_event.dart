import 'package:equatable/equatable.dart';

sealed class NotificationsEvent extends Equatable {
  const NotificationsEvent();

  @override
  List<Object?> get props => [];
}

final class NotificationsLoadRequested extends NotificationsEvent {
  const NotificationsLoadRequested();
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
