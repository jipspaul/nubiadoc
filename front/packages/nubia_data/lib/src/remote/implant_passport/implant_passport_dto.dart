import 'package:nubia_domain/src/entities/implant_item.dart';

class ImplantItemDto {
  final String id;
  final String brand;
  final String? lotNumber;
  final String? placementDate;
  final String? toothPosition;
  final String? notes;
  final String? lastControlDate;
  final String? nextControl;
  final String? manufacturer;
  final String? model;
  final String? reference;
  final String? dimensions;
  final String? material;

  const ImplantItemDto({
    required this.id,
    required this.brand,
    this.lotNumber,
    this.placementDate,
    this.toothPosition,
    this.notes,
    this.lastControlDate,
    this.nextControl,
    this.manufacturer,
    this.model,
    this.reference,
    this.dimensions,
    this.material,
  });

  factory ImplantItemDto.fromJson(Map<String, dynamic> json) => ImplantItemDto(
        id: json['id'] as String,
        brand: json['brand'] as String,
        lotNumber: json['lot_number'] as String?,
        placementDate: json['placement_date'] as String?,
        toothPosition: json['tooth_position'] as String?,
        notes: json['notes'] as String?,
        lastControlDate: json['last_control_date'] as String?,
        nextControl: json['next_control'] as String?,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        reference: json['reference'] as String?,
        dimensions: json['dimensions'] as String?,
        material: json['material'] as String?,
      );

  ImplantItem toDomain() => ImplantItem(
        id: id,
        brand: brand,
        lotNumber: lotNumber,
        placementDate: placementDate,
        toothPosition: toothPosition,
        notes: notes,
        lastControlDate: lastControlDate,
        nextControl: nextControl,
        manufacturer: manufacturer,
        model: model,
        reference: reference,
        dimensions: dimensions,
        material: material,
      );
}
