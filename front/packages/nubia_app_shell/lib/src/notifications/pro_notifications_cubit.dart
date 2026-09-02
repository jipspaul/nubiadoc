import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_notifications_state.dart';

/// Backs the pro shell's notification bell (#6263) : badge non-lus + panneau
/// liste, partagés par les 3 apps pro (praticien/secrétariat/pharmacie) via
/// [ProShell].
///
/// Le badge se rafraîchit tout seul (60s + retour au premier plan, cf.
/// [ProShell]'s `WidgetsBindingObserver`) via `?unread_only=true` — bien
/// moins coûteux que de recharger la liste complète en continu. La liste
/// complète, elle, n'est chargée qu'à l'ouverture du panneau ([loadList]).
class ProNotificationsCubit extends Cubit<ProNotificationsState> {
  ProNotificationsCubit({required NotificationRepository repository})
      : _repository = repository,
        super(const ProNotificationsState()) {
    refreshUnreadCount();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => refreshUnreadCount(),
    );
  }

  final NotificationRepository _repository;
  Timer? _pollTimer;

  Future<void> refreshUnreadCount() async {
    final result = await _repository.getNotifications(unreadOnly: true);
    result.fold(
      (_) {}, // échec silencieux : le badge garde son dernier compte connu.
      (notifications) =>
          emit(state.copyWith(unreadCount: notifications.length)),
    );
  }

  Future<void> loadList() async {
    emit(state.copyWith(isLoadingList: true, error: null));
    final result = await _repository.getNotifications();
    result.fold(
      (failure) => emit(
        state.copyWith(isLoadingList: false, error: failure.message),
      ),
      (notifications) => emit(
        state.copyWith(
          isLoadingList: false,
          notifications: notifications,
          unreadCount: notifications.where((n) => !n.read).length,
        ),
      ),
    );
  }

  Future<void> markRead(String notificationId) async {
    final current = state.notifications;
    if (current != null) {
      final updated = [
        for (final n in current)
          n.id == notificationId ? n.copyWith(read: true) : n,
      ];
      emit(
        state.copyWith(
          notifications: updated,
          unreadCount: updated.where((n) => !n.read).length,
        ),
      );
    }
    await _repository.markRead(notificationId);
  }

  Future<void> markAllRead() async {
    final current = state.notifications;
    emit(
      state.copyWith(
        notifications: current == null
            ? null
            : [for (final n in current) n.copyWith(read: true)],
        unreadCount: 0,
      ),
    );
    await _repository.markAllRead();
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
