import 'package:nubia_domain/src/entities/stock_location.dart';

class StockLocationDto {
  final String id;
  final String name;
  final bool isMain;

  const StockLocationDto({
    required this.id,
    required this.name,
    required this.isMain,
  });

  factory StockLocationDto.fromJson(Map<String, dynamic> json) =>
      StockLocationDto(
        id: json['id'] as String,
        name: json['name'] as String,
        isMain: json['is_main'] as bool,
      );

  StockLocation toDomain() =>
      StockLocation(id: id, name: name, isMain: isMain);
}
