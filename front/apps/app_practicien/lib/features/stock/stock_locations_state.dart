import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class StockLocationsState extends Equatable {
  const StockLocationsState();
}

class StockLocationsLoading extends StockLocationsState {
  const StockLocationsLoading();

  @override
  List<Object?> get props => [];
}

class StockLocationsLoaded extends StockLocationsState {
  const StockLocationsLoaded({
    required this.locations,
    required this.items,
    required this.itemLocations,
    this.submittingItemId,
    this.deletingLocationId,
  });

  final List<StockLocation> locations;
  final List<StockItem> items;

  /// Stock (quantité + seuil) de chaque article par localisation, indexé par
  /// `item.id` — une entrée par localisation du cabinet.
  final Map<String, List<StockItemLocation>> itemLocations;

  /// Id de l'article dont un transfert/réglage de seuil est en cours
  /// (bouton en loading), `null` si aucune soumission en cours.
  final String? submittingItemId;

  /// Id de la localisation en cours de suppression (#7452), `null` si
  /// aucune suppression en cours.
  final String? deletingLocationId;

  @override
  List<Object?> get props =>
      [locations, items, itemLocations, submittingItemId, deletingLocationId];
}

class StockLocationsError extends StockLocationsState {
  const StockLocationsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
