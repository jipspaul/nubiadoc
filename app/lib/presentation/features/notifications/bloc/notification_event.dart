import 'package:equatable/equatable.dart';

sealed class NotificationEvent extends Equatable {
  const NotificationEvent();

  @override
  List<Object?> get props => [];
}

final class NotificationsLoadRequested extends NotificationEvent {
  const NotificationsLoadRequested();
}

final class NotificationMarkReadRequested extends NotificationEvent {
  final String notificationId;

  const NotificationMarkReadRequested(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

final class NotificationMarkAllReadRequested extends NotificationEvent {
  const NotificationMarkAllReadRequested();
}

final class NotificationReceived extends NotificationEvent {
  final String title;
  final String body;
  final String? deepLink;

  const NotificationReceived({
    required this.title,
    required this.body,
    this.deepLink,
  });

  @override
  List<Object?> get props => [title, body, deepLink];
}

final class NotificationOptInRequested extends NotificationEvent {
  const NotificationOptInRequested();
}
