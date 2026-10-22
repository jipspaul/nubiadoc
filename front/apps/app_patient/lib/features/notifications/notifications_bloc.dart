import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
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

  // Facette courante — mémorisée ici (pas seulement dans l'état) pour que
  // `_onLoadMore` continue de paginer la MÊME famille au défilement (#8357) :
  // source unique avec `NotificationsLoaded.facet`.
  NotificationType? _facet;

  NotificationsBloc({required NotificationRepository repository})
      : _repository = repository,
        super(const NotificationsInitial()) {
    on<NotificationsLoadRequested>(_onLoadRequested);
    on<NotificationsLoadMoreRequested>(_onLoadMore);
    on<NotificationsUnreadCountRequested>(_onUnreadCountRequested);
    on<NotificationMarkReadRequested>(_onMarkRead);
    on<NotificationMarkAllReadRequested>(_onMarkAllRead);
    on<NotificationFacetSelected>(_onFacetSelected);
  }

  /// Appelle `getPage` pour la facette/le curseur courants — sans [cursor]
  /// ni facette sélectionnée, forme d'appel identique à avant #8357
  /// (`getPage(limit: _pageSize)`), pour ne pas changer la requête émise
  /// par le chargement initial / le défilement tant qu'aucune facette
  /// n'est active.
  Future<Either<Failure, PagedNotifications>> _fetchPage({String? cursor}) {
    if (_facet == null) {
      return cursor == null
          ? _repository.getPage(limit: _pageSize)
          : _repository.getPage(limit: _pageSize, cursor: cursor);
    }
    return cursor == null
        ? _repository.getPage(limit: _pageSize, type: _facet)
        : _repository.getPage(limit: _pageSize, cursor: cursor, type: _facet);
  }

  Future<void> _onLoadRequested(
    NotificationsLoadRequested event,
    Emitter<NotificationsState> emit,
  ) async {
    _facet = null;
    emit(const NotificationsLoading());
    try {
      final result = await _fetchPage();
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

  /// Sélection d'une puce de facette (#8357 — régression de #8342) : refait
  /// l'appel serveur avec `?type=` plutôt que de filtrer côté client les
  /// notifications déjà chargées (une seule page, #8323) — sinon la liste
  /// et le compteur de la puce ne parlent plus du même ensemble (puce
  /// « Documents 25 » ouvrant une liste vide quand la page chargée ne
  /// contient aucun document). `total`/`typeCounts`/`unreadTotal` sont
  /// préservés : ils décrivent la boîte ENTIÈRE (#8342/#8358), indépendante
  /// de la facette affichée.
  Future<void> _onFacetSelected(
    NotificationFacetSelected event,
    Emitter<NotificationsState> emit,
  ) async {
    final current = state;
    if (current is! NotificationsLoaded) return;
    final previousFacet = _facet;
    final previousCursor = _cursor;
    _facet = event.facet;
    _cursor = null;
    try {
      final result = await _fetchPage();
      result.fold(
        (failure) {
          // Rollback : la facette/le curseur internes doivent rester en
          // phase avec l'état émis (qui garde `current.facet`), sinon le
          // prochain `NotificationsLoadMoreRequested` paginerait la
          // mauvaise famille.
          _facet = previousFacet;
          _cursor = previousCursor;
          safeEmit(NotificationsLoaded(
            current.notifications,
            hasMore: current.hasMore,
            total: current.total,
            typeCounts: current.typeCounts,
            unreadTotal: current.unreadTotal,
            facet: current.facet,
            actionError: failure.message,
          ));
        },
        (page) {
          _cursor = page.nextCursor;
          safeEmit(NotificationsLoaded(
            page.notifications,
            hasMore: page.nextCursor != null,
            total: current.total,
            typeCounts: current.typeCounts,
            unreadTotal: current.unreadTotal,
            facet: event.facet,
          ));
        },
      );
    } catch (e) {
      _facet = previousFacet;
      _cursor = previousCursor;
      safeEmit(NotificationsLoaded(
        current.notifications,
        hasMore: current.hasMore,
        total: current.total,
        typeCounts: current.typeCounts,
        unreadTotal: current.unreadTotal,
        facet: current.facet,
        actionError: e.toString(),
      ));
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
      final result = await _fetchPage(cursor: _cursor);
      result.fold(
        (failure) => safeEmit(current.copyWith(isLoadingMore: false)),
        (page) {
          _cursor = page.nextCursor;
          safeEmit(current.copyWith(
            notifications: [...current.notifications, ...page.notifications],
            // Sous une facette, `page.total` est le total de CETTE
            // famille (#8357, `?type=`), pas celui de la boîte entière
            // affiché par la puce « Toutes » (#8342) — ne l'adopter que
            // hors facette, pour ne pas écraser `current.total` avec un
            // chiffre plus petit au défilement.
            total: _facet == null ? (page.total ?? current.total) : current.total,
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
