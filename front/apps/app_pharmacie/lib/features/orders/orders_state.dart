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

  /// Sans filtre explicite (« Toutes »), la file de travail exclut les
  /// commandes terminales (retirées/refusées/annulées, déjà soldées) —
  /// chacune reste consultable via sa propre facette (#7003 : sans ça, une
  /// commande delivrée devenait injoignable, aucune facette ni la recherche
  /// ne la couvrant). Triée d'abord par ce qu'il reste à faire (reçue >
  /// en préparation > prête), puis par réception croissante dans chaque
  /// groupe : la commande la plus ancienne encore à préparer est toujours en
  /// tête, jamais enfouie sous des commandes déjà prêtes (#7711).
  List<PharmacyOrder> get visible {
    final matching = filter == null
        ? orders.where((order) => !order.status.isTerminal)
        : orders.where((order) => order.status == filter);
    return matching.toList()
      ..sort((a, b) {
        final workOrder = _workPriority(a.status) - _workPriority(b.status);
        if (workOrder != 0) return workOrder;
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  /// Rang de priorité de travail d'un statut actif : plus petit = plus
  /// urgent à traiter. Les commandes déjà prêtes (travail terminé, en
  /// attente du patient) passent après celles encore à préparer.
  static int _workPriority(PharmacyOrderStatus status) {
    switch (status) {
      case PharmacyOrderStatus.received:
        return 0;
      case PharmacyOrderStatus.preparing:
        return 1;
      case PharmacyOrderStatus.ready:
        return 2;
      case PharmacyOrderStatus.pickedUp:
      case PharmacyOrderStatus.rejected:
      case PharmacyOrderStatus.cancelled:
        return 3;
    }
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
