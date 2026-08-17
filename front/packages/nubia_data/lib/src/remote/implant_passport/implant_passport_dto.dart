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
  final String? material;
  final bool? mriCompatibility;

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
        material: json['material'] as String?,
        mriCompatibility: json['mri_compatibility'] as bool?,
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
        material: material,
        mriCompatibility: mriCompatibility,
      );
}
