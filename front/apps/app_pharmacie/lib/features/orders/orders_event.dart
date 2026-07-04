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

/// Nouvelle photographie de la file reçue du flux temps réel.
class OrdersStreamUpdated extends OrdersEvent {
  const OrdersStreamUpdated(this.orders);

  final List<PharmacyOrder> orders;

  @override
  List<Object?> get props => [orders];
}
