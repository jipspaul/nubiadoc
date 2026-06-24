import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'notifications_event.dart';
import 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  final NotificationRepository _repository;

  NotificationsBloc({required NotificationRepository repository})
      : _repository = repository,
        super(const NotificationsInitial()) {
    on<NotificationsLoadRequested>(_onLoadRequested);
    on<NotificationMarkReadRequested>(_onMarkRead);
    on<NotificationMarkAllReadRequested>(_onMarkAllRead);
  }

  Future<void> _onLoadRequested(
    NotificationsLoadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    emit(const NotificationsLoading());
    try {
      final result = await _repository.getNotifications();
      result.fold(
        (failure) => emit(NotificationsError(failure.message)),
        (notifications) => emit(NotificationsLoaded(notifications)),
      );
    } catch (_) {
      emit(const NotificationsError('Erreur de chargement.'));
    }
  }

  Future<void> _onMarkRead(
    NotificationMarkReadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    final updated = current.notifications.map((n) {
      return n.id == event.notificationId ? n.copyWith(read: true) : n;
    }).toList();
    emit(current.copyWith(notifications: updated));

    try {
      await _repository.markRead(event.notificationId);
    } catch (_) {}
  }

  Future<void> _onMarkAllRead(
    NotificationMarkAllReadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    final updated =
        current.notifications.map((n) => n.copyWith(read: true)).toList();
    emit(current.copyWith(notifications: updated));

    try {
      await _repository.markAllRead();
    } catch (_) {}
  }
}
