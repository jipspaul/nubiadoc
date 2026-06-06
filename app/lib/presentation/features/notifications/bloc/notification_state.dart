import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/app_notification.dart';

sealed class NotificationState extends Equatable {
  const NotificationState();

  @override
  List<Object?> get props => [];
}

final class NotificationInitial extends NotificationState {
  const NotificationInitial();
}

final class NotificationLoading extends NotificationState {
  const NotificationLoading();
}

final class NotificationLoaded extends NotificationState {
  final List<AppNotification> notifications;

  const NotificationLoaded(this.notifications);

  int get unreadCount => notifications.where((n) => !n.read).length;

  NotificationLoaded copyWith({List<AppNotification>? notifications}) {
    return NotificationLoaded(notifications ?? this.notifications);
  }

  @override
  List<Object?> get props => [notifications];
}

final class NotificationError extends NotificationState {
  final String message;

  const NotificationError(this.message);

  @override
  List<Object?> get props => [message];
}
