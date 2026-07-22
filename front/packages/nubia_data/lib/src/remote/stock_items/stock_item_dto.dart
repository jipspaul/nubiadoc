import 'package:nubia_domain/src/entities/stock_item.dart';

class StockItemDto {
  final String id;
  final String reference;
  final String label;
  final String unit;
  final int quantityOnHand;
  final int? alertThreshold;

  const StockItemDto({
    required this.id,
    required this.reference,
    required this.label,
    required this.unit,
    required this.quantityOnHand,
    this.alertThreshold,
  });

  factory StockItemDto.fromJson(Map<String, dynamic> json) => StockItemDto(
        id: json['id'] as String,
        reference: json['reference'] as String,
        label: json['label'] as String,
        unit: json['unit'] as String,
        quantityOnHand: json['quantity_on_hand'] as int,
        alertThreshold: json['alert_threshold'] as int?,
      );

  StockItem toDomain() => StockItem(
        id: id,
        reference: reference,
        label: label,
        unit: unit,
        quantityOnHand: quantityOnHand,
        alertThreshold: alertThreshold,
      );
}
