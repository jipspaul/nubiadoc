import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/app_notification.dart';
import 'package:nubia_patient/domain/repositories/notification_repository.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_event.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_state.dart';

@injectable
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository _repository;

  NotificationBloc(this._repository) : super(const NotificationInitial()) {
    on<NotificationsLoadRequested>(_onLoadRequested);
    on<NotificationMarkReadRequested>(_onMarkRead);
    on<NotificationMarkAllReadRequested>(_onMarkAllRead);
    on<NotificationReceived>(_onReceived);
    on<NotificationOptInRequested>(_onOptIn);
  }

  Future<void> _onLoadRequested(
    NotificationsLoadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    emit(const NotificationLoading());
    final result = await _repository.getNotifications();
    result.fold(
      (failure) => emit(NotificationError(failure.message)),
      (notifications) => emit(NotificationLoaded(notifications)),
    );
  }

  Future<void> _onMarkRead(
    NotificationMarkReadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final current = state;
    if (current is! NotificationLoaded) return;

    // Optimistic update.
    final updated = current.notifications.map((n) {
      return n.id == event.notificationId ? n.copyWith(read: true) : n;
    }).toList();
    emit(current.copyWith(notifications: updated));

    // Best-effort server sync; ignore failure.
    await _repository.markRead(event.notificationId);
  }

  Future<void> _onMarkAllRead(
    NotificationMarkAllReadRequested event,
    Emitter<NotificationState> emit,
  ) async {
    final current = state;
    if (current is! NotificationLoaded) return;

    final updated = current.notifications
        .map((n) => n.copyWith(read: true))
        .toList();
    emit(current.copyWith(notifications: updated));

    await _repository.markAllRead();
  }

  void _onReceived(
    NotificationReceived event,
    Emitter<NotificationState> emit,
  ) {
    final current = state;
    if (current is! NotificationLoaded) return;

    // Prepend the incoming push notification to the list.
    final incoming = AppNotification(
      id: 'fcm-${DateTime.now().millisecondsSinceEpoch}',
      type: _inferType(event.deepLink),
      title: event.title,
      body: event.body,
      read: false,
      createdAt: DateTime.now(),
      deepLink: event.deepLink,
    );
    emit(current.copyWith(notifications: [incoming, ...current.notifications]));
  }

  Future<void> _onOptIn(
    NotificationOptInRequested event,
    Emitter<NotificationState> emit,
  ) async {
    // Token registration is handled by FcmService; nothing to emit here.
  }

  static NotificationType _inferType(String? deepLink) {
    if (deepLink == null) return NotificationType.other;
    if (deepLink.contains('/appointments')) return NotificationType.appointment;
    if (deepLink.contains('/messages')) return NotificationType.message;
    if (deepLink.contains('/documents')) return NotificationType.document;
    if (deepLink.contains('/billing')) return NotificationType.payment;
    return NotificationType.other;
  }
}
