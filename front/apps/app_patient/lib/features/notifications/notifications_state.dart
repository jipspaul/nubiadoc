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

  /// `true` tant qu'une page suivante reste à charger (`page.next_cursor`
  /// non nul à la dernière page récupérée) — #8323 : la liste se charge
  /// page par page à la demande (défilement) plutôt qu'en une seule
  /// pagination exhaustive avant le premier rendu.
  final bool hasMore;

  /// Chargement de la page suivante en cours (défilement) — affiche un
  /// indicateur en pied de liste plutôt qu'un rechargement complet.
  final bool isLoadingMore;

  /// Volume complet de la boîte (`page.total`, #8342) — peut dépasser
  /// [notifications.length] tant que toutes les pages n'ont pas été
  /// chargées. `null` si inconnu (ex. construit sans, en test) : l'écran
  /// retombe alors sur [notifications.length].
  final int? total;

  /// Comptes par famille sur la boîte ENTIÈRE (#8342) — alimente les puces
  /// de facette « Rendez-vous »/« Documents »/« Paiements » ; indépendant
  /// de [notifications.length], qui ne couvre que les pages déjà chargées
  /// (#8323). Vide si pas encore connu (ex. échec de la requête de
  /// comptage) : l'écran retombe alors sur 0 pour ces puces.
  final Map<NotificationType, int> typeCounts;

  /// Total réel de non-lus de la boîte ENTIÈRE (`page.unread_count`, #6279)
  /// — même source déjà utilisée pour la pastille de la cloche
  /// (`NotificationRepository.getUnreadCount`), portée ici pour que le
  /// sous-titre « N non lues » de l'en-tête ne dépende plus de
  /// [notifications.length] (borné à une page, #8323 — jumeau de #8342).
  /// `null` si pas encore connu : l'écran retombe alors sur [unreadCount].
  final int? unreadTotal;

  /// Facette sélectionnée (#8357 — régression de #8342) : source de vérité
  /// de la puce active ET du filtre serveur `?type=` appliqué à
  /// [notifications], qui sont donc déjà la liste filtrée — plus de filtre
  /// client sur une page qui ne parlait pas du même ensemble que le
  /// compteur de la puce.
  final NotificationType? facet;

  const NotificationsLoaded(
    this.notifications, {
    this.actionError,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.total,
    this.typeCounts = const {},
    this.unreadTotal,
    this.facet,
  });

  int get unreadCount => notifications.where((n) => !n.read).length;

  NotificationsLoaded copyWith({
    List<AppNotification>? notifications,
    String? actionError,
    bool clearActionError = false,
    bool? hasMore,
    bool? isLoadingMore,
    int? total,
    Map<NotificationType, int>? typeCounts,
    int? unreadTotal,
  }) {
    return NotificationsLoaded(
      notifications ?? this.notifications,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      total: total ?? this.total,
      typeCounts: typeCounts ?? this.typeCounts,
      unreadTotal: unreadTotal ?? this.unreadTotal,
      // La facette n'a pas de paramètre dédié ici : seul
      // `NotificationFacetSelected` la change, en construisant un nouveau
      // `NotificationsLoaded` directement (#8357) — sinon elle devrait
      // pouvoir être remise à `null` (« Toutes »), ce que le sentinel
      // `?? this.x` de `copyWith` ne permet pas.
      facet: facet,
    );
  }

  @override
  List<Object?> get props => [
        notifications,
        actionError,
        hasMore,
        isLoadingMore,
        total,
        typeCounts,
        unreadTotal,
        facet,
      ];
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
