import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class NotificationsEvent extends Equatable {
  const NotificationsEvent();

  @override
  List<Object?> get props => [];
}

final class NotificationsLoadRequested extends NotificationsEvent {
  const NotificationsLoadRequested();
}

/// Charge uniquement `page.unread_count` (#6279), pas la liste paginée —
/// pour l'accueil, qui n'a besoin que du booléen « pastille sur la cloche »
/// (#7102).
final class NotificationsUnreadCountRequested extends NotificationsEvent {
  const NotificationsUnreadCountRequested();
}

final class NotificationMarkReadRequested extends NotificationsEvent {
  final String notificationId;

  const NotificationMarkReadRequested(this.notificationId);

  @override
  List<Object?> get props => [notificationId];
}

final class NotificationMarkAllReadRequested extends NotificationsEvent {
  const NotificationMarkAllReadRequested();
}

/// Défilement proche du bas de la liste (#8323) : charge la page suivante
/// via `page.next_cursor` plutôt que tout charger avant le premier rendu —
/// même correctif que `DocumentsLoadMoreRequested` pour #8297.
final class NotificationsLoadMoreRequested extends NotificationsEvent {
  const NotificationsLoadMoreRequested();
}

/// Sélection d'une puce de facette (#8357 — régression de #8342) : refait
/// l'appel serveur avec `?type=`, pour que la liste ouverte corresponde au
/// même ensemble que le compteur affiché sur la puce, plutôt qu'un filtre
/// côté client sur la seule page déjà chargée (#8323).
final class NotificationFacetSelected extends NotificationsEvent {
  final NotificationType? facet;

  const NotificationFacetSelected(this.facet);

  @override
  List<Object?> get props => [facet];
}
