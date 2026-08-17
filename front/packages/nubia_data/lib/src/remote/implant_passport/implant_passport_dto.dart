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
  final String? practitioner;
  final String? office;
  final String? prosthesis;
  final String? manufacturer;
  final String? model;
  final String? reference;
  final String? dimensions;
  final String? material;
  final String? mriCompatibility;

  const ImplantItemDto({
    required this.id,
    required this.brand,
    this.lotNumber,
    this.placementDate,
    this.toothPosition,
    this.notes,
    this.lastControlDate,
    this.nextControl,
    this.practitioner,
    this.office,
    this.prosthesis,
    this.manufacturer,
    this.model,
    this.reference,
    this.dimensions,
    this.material,
    this.mriCompatibility,
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
        practitioner: json['practitioner'] as String?,
        office: json['office'] as String?,
        prosthesis: json['prosthesis'] as String?,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        reference: json['reference'] as String?,
        dimensions: json['dimensions'] as String?,
        material: json['material'] as String?,
        mriCompatibility: json['mri_compatibility'] as String?,
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
        practitioner: practitioner,
        office: office,
        prosthesis: prosthesis,
        manufacturer: manufacturer,
        model: model,
        reference: reference,
        dimensions: dimensions,
        material: material,
        mriCompatibility: mriCompatibility,
      );
}
