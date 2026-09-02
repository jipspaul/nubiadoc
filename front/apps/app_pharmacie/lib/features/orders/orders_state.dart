import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class OrdersState extends Equatable {
  const OrdersState();

  @override
  List<Object?> get props => [];
}

class OrdersLoading extends OrdersState {
  const OrdersLoading();
}

class OrdersLoaded extends OrdersState {
  OrdersLoaded({
    required this.orders,
    this.filter,
    this.pendingOrderId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// File complète (non filtrée) — le filtre s'applique à l'affichage.
  final List<PharmacyOrder> orders;
  final PharmacyOrderStatus? filter;

  /// Commande dont la transition de ligne (Préparer/Marquer prête) est en
  /// cours — pilote le loading du bouton de la ligne concernée.
  final String? pendingOrderId;

  /// Instant de réception des données affichées — source de l'indicateur
  /// de fraîcheur (« Mise à jour il y a N s »).
  final DateTime updatedAt;

  /// Sans filtre explicite, la file de travail exclut les commandes
  /// terminales (retirées/refusées/annulées, déjà soldées) — la maquette
  /// ne prévoit aucune facette pour les revoir depuis cet écran. Triée par
  /// réception croissante : la commande la plus ancienne (donc la plus
  /// urgente) est toujours en tête, jamais enfouie sous des lignes plus
  /// récentes.
  List<PharmacyOrder> get visible {
    final matching = filter == null
        ? orders.where((order) => !order.status.isTerminal)
        : orders.where((order) => order.status == filter);
    return matching.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  // updatedAt est un horodatage d'affichage (indicateur de fraîcheur), pas
  // une donnée métier : exclu des props pour ne pas casser l'égalité entre
  // deux chargements identiques (bloc_test, cache de state).
  @override
  List<Object?> get props => [orders, filter, pendingOrderId];
}

class OrdersError extends OrdersState {
  const OrdersError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
