import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'notifications_event.dart';
import 'notifications_state.dart';

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState>
    with SafeEmitMixin<NotificationsState> {
  final NotificationRepository _repository;

  // Taille de page (#8323) : bornée plutôt que de suivre les curseurs
  // jusqu'à épuisement avant le premier rendu — cf. doctrine #8279.
  static const _pageSize = 20;

  // Curseur de la dernière page chargée — mémorisé ici (et non dans l'état)
  // au même titre que pour `DocumentsBloc` : détail de chargement interne,
  // pas une information affichée à l'écran.
  String? _cursor;

  NotificationsBloc({required NotificationRepository repository})
      : _repository = repository,
        super(const NotificationsInitial()) {
    on<NotificationsLoadRequested>(_onLoadRequested);
    on<NotificationsLoadMoreRequested>(_onLoadMore);
    on<NotificationsUnreadCountRequested>(_onUnreadCountRequested);
    on<NotificationMarkReadRequested>(_onMarkRead);
    on<NotificationMarkAllReadRequested>(_onMarkAllRead);
  }

  Future<void> _onLoadRequested(
    NotificationsLoadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    emit(const NotificationsLoading());
    try {
      final result = await _repository.getPage(limit: _pageSize);
      await result.fold(
        (failure) async => safeEmit(NotificationsError(failure.message)),
        (page) async {
          _cursor = page.nextCursor;
          safeEmit(page.notifications.isEmpty
              ? const NotificationsEmpty()
              : NotificationsLoaded(
                  page.notifications,
                  total: page.total,
                  hasMore: page.nextCursor != null,
                  typeCounts: await _loadTypeCounts(),
                  unreadTotal: await _loadUnreadTotal(),
                ));
        },
      );
    } catch (e) {
      safeEmit(NotificationsError(e.toString()));
    }
  }

  /// Comptes par famille (#8342) — best-effort : un échec ne doit pas
  /// empêcher l'affichage de la liste déjà chargée, seulement réduire les
  /// puces « Rendez-vous »/« Documents »/« Paiements » à 0.
  Future<Map<NotificationType, int>> _loadTypeCounts() async {
    try {
      final result = await _repository.typeCounts();
      return result.fold((_) => const {}, (counts) => counts);
    } catch (_) {
      return const {};
    }
  }

  /// Total réel de non-lus de la boîte (`page.unread_count`, #6279) —
  /// best-effort comme [_loadTypeCounts] : un échec ne doit pas empêcher
  /// l'affichage de la liste, seulement faire retomber le sous-titre de
  /// l'en-tête sur [NotificationsLoaded.unreadCount] (#8358, jumeau de
  /// #8342 pour ce même sous-titre).
  Future<int?> _loadUnreadTotal() async {
    try {
      final result = await _repository.getUnreadCount();
      return result.fold((_) => null, (count) => count);
    } catch (_) {
      return null;
    }
  }

  /// Charge la page suivante (#8323) — déclenché par le défilement proche
  /// du bas de la liste. No-op si une page est déjà en cours de chargement
  /// ou si la dernière page récupérée n'a pas de curseur suivant.
  Future<void> _onLoadMore(
    NotificationsLoadMoreRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    final current = state;
    if (current is! NotificationsLoaded ||
        !current.hasMore ||
        current.isLoadingMore ||
        _cursor == null) {
      return;
    }
    safeEmit(current.copyWith(isLoadingMore: true));
    try {
      final result =
          await _repository.getPage(limit: _pageSize, cursor: _cursor);
      result.fold(
        (failure) => safeEmit(current.copyWith(isLoadingMore: false)),
        (page) {
          _cursor = page.nextCursor;
          safeEmit(current.copyWith(
            notifications: [...current.notifications, ...page.notifications],
            total: page.total ?? current.total,
            hasMore: page.nextCursor != null,
            isLoadingMore: false,
          ));
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onUnreadCountRequested(
    NotificationsUnreadCountRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    emit(const NotificationsLoading());
    try {
      final result = await _repository.getUnreadCount();
      result.fold(
        (failure) => safeEmit(NotificationsError(failure.message)),
        (count) => safeEmit(NotificationsUnreadCountLoaded(count)),
      );
    } catch (e) {
      safeEmit(NotificationsError(e.toString()));
    }
  }

  Future<void> _onMarkRead(
    NotificationMarkReadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    final original = current.notifications;
    final updated = original.map((n) {
      return n.id == event.notificationId ? n.copyWith(read: true) : n;
    }).toList();
    final wasUnread =
        original.any((n) => n.id == event.notificationId && !n.read);
    emit(current.copyWith(
      notifications: updated,
      clearActionError: true,
      // Décompte optimiste du total serveur (#8358) — sinon le sous-titre
      // de l'en-tête resterait figé sur l'ancienne valeur jusqu'au
      // prochain NotificationsLoadRequested.
      unreadTotal: wasUnread && current.unreadTotal != null
          ? current.unreadTotal! - 1
          : current.unreadTotal,
    ));

    try {
      final result = await _repository.markRead(event.notificationId);
      result.fold(
        (failure) => safeEmit(current.copyWith(
          notifications: original,
          actionError: failure.message,
        )),
        (_) {},
      );
    } catch (e) {
      safeEmit(current.copyWith(
        notifications: original,
        actionError: e.toString(),
      ));
    }
  }

  Future<void> _onMarkAllRead(
    NotificationMarkAllReadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    final current = state;
    if (current is! NotificationsLoaded) return;

    final original = current.notifications;
    final updated =
        original.map((n) => n.copyWith(read: true)).toList();
    // Toutes lues → 0 non-lues (#8358), que [unreadTotal] ait déjà été
    // connu ou non.
    emit(current.copyWith(
      notifications: updated,
      clearActionError: true,
      unreadTotal: 0,
    ));

    try {
      final result = await _repository.markAllRead();
      result.fold(
        (failure) => safeEmit(current.copyWith(
          notifications: original,
          actionError: failure.message,
        )),
        (_) {},
      );
    } catch (e) {
      safeEmit(current.copyWith(
        notifications: original,
        actionError: e.toString(),
      ));
    }
  }
}
