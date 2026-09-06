import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class NotificationsState extends Equatable {
  const NotificationsState();

  @override
  List<Object?> get props => [];
}

final class NotificationsInitial extends NotificationsState {
  const NotificationsInitial();
}

final class NotificationsLoading extends NotificationsState {
  const NotificationsLoading();
}

final class NotificationsLoaded extends NotificationsState {
  final List<AppNotification> notifications;
  final String? actionError;

  const NotificationsLoaded(this.notifications, {this.actionError});

  int get unreadCount => notifications.where((n) => !n.read).length;

  NotificationsLoaded copyWith({
    List<AppNotification>? notifications,
    String? actionError,
    bool clearActionError = false,
  }) {
    return NotificationsLoaded(
      notifications ?? this.notifications,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }

  @override
  List<Object?> get props => [notifications, actionError];
}

final class NotificationsEmpty extends NotificationsState {
  const NotificationsEmpty();
}

final class NotificationsError extends NotificationsState {
  final String message;

  const NotificationsError(this.message);

  @override
  List<Object?> get props => [message];
}
