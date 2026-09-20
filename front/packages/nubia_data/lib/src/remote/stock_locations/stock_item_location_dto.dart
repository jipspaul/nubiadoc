import 'package:nubia_domain/src/entities/stock_item_location.dart';

class StockItemLocationDto {
  final String locationId;
  final String locationName;
  final bool isMain;
  final int quantity;
  final int? threshold;

  const StockItemLocationDto({
    required this.locationId,
    required this.locationName,
    required this.isMain,
    required this.quantity,
    this.threshold,
  });

  factory StockItemLocationDto.fromJson(Map<String, dynamic> json) =>
      StockItemLocationDto(
        locationId: json['location_id'] as String,
        locationName: json['location_name'] as String,
        isMain: json['is_main'] as bool,
        quantity: json['quantity'] as int,
        threshold: json['threshold'] as int?,
      );

  StockItemLocation toDomain() => StockItemLocation(
        locationId: locationId,
        locationName: locationName,
        isMain: isMain,
        quantity: quantity,
        threshold: threshold,
      );
}
