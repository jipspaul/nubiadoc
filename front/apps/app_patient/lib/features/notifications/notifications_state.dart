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

/// Total serveur de non-lus (#6279), sans la liste — utilisé par l'accueil
/// pour la pastille de la cloche, sans payer la pagination complète (#7102).
final class NotificationsUnreadCountLoaded extends NotificationsState {
  final int unreadCount;

  const NotificationsUnreadCountLoaded(this.unreadCount);

  @override
  List<Object?> get props => [unreadCount];
}

final class NotificationsError extends NotificationsState {
  final String message;

  const NotificationsError(this.message);

  @override
  List<Object?> get props => [message];
}
