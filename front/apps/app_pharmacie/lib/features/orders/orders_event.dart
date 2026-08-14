import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class OrdersEvent extends Equatable {
  const OrdersEvent();

  @override
  List<Object?> get props => [];
}

/// Chargement initial + abonnement au flux temps réel.
class OrdersSubscribed extends OrdersEvent {
  const OrdersSubscribed();
}

/// Pull-to-refresh / bouton réessayer.
class OrdersRefreshRequested extends OrdersEvent {
  const OrdersRefreshRequested();
}

/// Filtre par statut (null = toutes).
class OrdersFilterChanged extends OrdersEvent {
  const OrdersFilterChanged(this.filter);

  final PharmacyOrderStatus? filter;

  @override
  List<Object?> get props => [filter];
}

/// Tick du rafraîchissement périodique auto (poste fixe au comptoir) — vient
/// s'ajouter au pull-to-refresh tactile, ne le remplace pas. Échec silencieux
/// (retry au tick suivant), comme le flux temps réel.
class OrdersAutoRefreshTicked extends OrdersEvent {
  const OrdersAutoRefreshTicked();
}

/// Nouvelle photographie de la file reçue du flux temps réel.
class OrdersStreamUpdated extends OrdersEvent {
  const OrdersStreamUpdated(this.orders);

  final List<PharmacyOrder> orders;

  @override
  List<Object?> get props => [orders];
}

/// Action de transition émise depuis la ligne — même sémantique que le
/// détail (`OrderDetailAcceptRequested`/`OrderDetailReadyRequested`) :
/// received→preparing ou preparing→ready. Le serveur reste l'autorité.
class OrdersTransitionRequested extends OrdersEvent {
  const OrdersTransitionRequested(this.orderId, this.target);

  final String orderId;
  final PharmacyOrderStatus target;

  @override
  List<Object?> get props => [orderId, target];
}
