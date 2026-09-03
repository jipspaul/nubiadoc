import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_notifications_state.dart';

/// Backs the pro shell's notification bell (#6263) : badge non-lus + panneau
/// liste, partagés par les 3 apps pro (praticien/secrétariat/pharmacie) via
/// [ProShell].
///
/// Le badge se rafraîchit tout seul (60s + retour au premier plan, cf.
/// [ProShell]'s `WidgetsBindingObserver`) via le total serveur
/// `page.unread_count` (#6279) — bien moins coûteux que de recharger la
/// liste complète en continu. La liste complète, elle, n'est chargée qu'à
/// l'ouverture du panneau ([loadList]).
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
    // Total serveur (#6279), pas la taille d'une page : `getNotifications`
    // plafonne à `limit` (20 par défaut), ce qui plafonnait le badge au lieu
    // de refléter le total réel de non-lus.
    final result = await _repository.getUnreadCount();
    result.fold(
      (_) {}, // échec silencieux : le badge garde son dernier compte connu.
      (count) => emit(state.copyWith(unreadCount: count)),
    );
  }

  Future<void> loadList() async {
    emit(state.copyWith(isLoadingList: true, error: null));
    final result = await _repository.getNotifications();
    await result.fold(
      (failure) async => emit(
        state.copyWith(isLoadingList: false, error: failure.message),
      ),
      (notifications) async {
        emit(
          state.copyWith(isLoadingList: false, notifications: notifications),
        );
        await refreshUnreadCount();
      },
    );
  }

  Future<void> markRead(String notificationId) async {
    final current = state.notifications;
    if (current != null) {
      // `state.unreadCount` est le total serveur (#6279), pas la taille de
      // `current` (qui peut être une simple page) : on le décrémente plutôt
      // que de le recalculer depuis `current`, sous peine de le faire
      // rechuter à la taille de la page affichée.
      final target = current.where((n) => n.id == notificationId);
      final wasUnread = target.isNotEmpty && !target.first.read;
      final updated = [
        for (final n in current)
          n.id == notificationId ? n.copyWith(read: true) : n,
      ];
      emit(
        state.copyWith(
          notifications: updated,
          unreadCount: wasUnread
              ? (state.unreadCount > 0 ? state.unreadCount - 1 : 0)
              : state.unreadCount,
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
