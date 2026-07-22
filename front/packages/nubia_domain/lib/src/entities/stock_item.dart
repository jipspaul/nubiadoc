import 'package:equatable/equatable.dart';

/// Un article d'inventaire cabinet (#4146). Source :
/// `GET /v1/cabinet/stock-items`.
class StockItem extends Equatable {
  final String id;
  final String reference;
  final String label;
  final String unit;
  final int quantityOnHand;
  final int? alertThreshold;

  const StockItem({
    required this.id,
    required this.reference,
    required this.label,
    required this.unit,
    required this.quantityOnHand,
    this.alertThreshold,
  });

  /// `true` si la quantité en stock est sous le seuil d'alerte configuré
  /// (pas d'alerte si `alertThreshold` absent).
  bool get isBelowAlertThreshold =>
      alertThreshold != null && quantityOnHand < alertThreshold!;

  StockItem copyWith({int? quantityOnHand}) => StockItem(
        id: id,
        reference: reference,
        label: label,
        unit: unit,
        quantityOnHand: quantityOnHand ?? this.quantityOnHand,
        alertThreshold: alertThreshold,
      );

  @override
  List<Object?> get props => [id, quantityOnHand];
}
