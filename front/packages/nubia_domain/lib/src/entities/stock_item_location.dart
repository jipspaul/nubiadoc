import 'package:equatable/equatable.dart';

/// La quantité (et le seuil d'alerte) d'un [StockItem] dans une localisation
/// donnée, #7182/#7183. Source : `GET /v1/cabinet/stock-items/:id/locations`.
class StockItemLocation extends Equatable {
  final String locationId;
  final String locationName;
  final bool isMain;
  final int quantity;
  final int? threshold;

  const StockItemLocation({
    required this.locationId,
    required this.locationName,
    required this.isMain,
    required this.quantity,
    this.threshold,
  });

  /// `true` si la quantité dans cette localisation est sous le seuil
  /// d'alerte configuré pour elle (pas d'alerte si `threshold` absent).
  bool get isBelowThreshold => threshold != null && quantity < threshold!;

  StockItemLocation copyWithQuantity(int quantity) => StockItemLocation(
        locationId: locationId,
        locationName: locationName,
        isMain: isMain,
        quantity: quantity,
        threshold: threshold,
      );

  /// `threshold: null` efface le seuil (distinct d'un paramètre omis).
  StockItemLocation copyWithThreshold(int? threshold) => StockItemLocation(
        locationId: locationId,
        locationName: locationName,
        isMain: isMain,
        quantity: quantity,
        threshold: threshold,
      );

  @override
  List<Object?> get props => [locationId, quantity, threshold];
}
