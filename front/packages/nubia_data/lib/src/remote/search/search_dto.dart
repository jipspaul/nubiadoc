import 'package:nubia_domain/src/entities/provider_result.dart';
import 'package:nubia_domain/src/entities/slot.dart';

class ProviderResultDto {
  final String id;
  final String displayName;
  final String specialty;
  final String? address;
  final double? distanceKm;

  const ProviderResultDto({
    required this.id,
    required this.displayName,
    required this.specialty,
    this.address,
    this.distanceKm,
  });

  factory ProviderResultDto.fromJson(Map<String, dynamic> json) =>
      ProviderResultDto(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        specialty: json['specialty'] as String,
        address: json['address'] as String?,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
      );

  ProviderResult toDomain() => ProviderResult(
        id: id,
        displayName: displayName,
        specialty: specialty,
        address: address,
        distanceKm: distanceKm,
      );
}

class SlotDto {
  final String id;
  final String cabinetId;
  final String practitionerId;
  final String startsAt;
  final String endsAt;
  final bool isAvailable;

  const SlotDto({
    required this.id,
    required this.cabinetId,
    required this.practitionerId,
    required this.startsAt,
    required this.endsAt,
    required this.isAvailable,
  });

  factory SlotDto.fromJson(Map<String, dynamic> json) => SlotDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        practitionerId: json['practitioner_id'] as String,
        startsAt: json['starts_at'] as String,
        endsAt: json['ends_at'] as String,
        isAvailable: json['is_available'] as bool? ?? true,
      );

  Slot toDomain() => Slot(
        id: id,
        cabinetId: cabinetId,
        practitionerId: practitionerId,
        startsAt: DateTime.parse(startsAt),
        endsAt: DateTime.parse(endsAt),
        isAvailable: isAvailable,
      );
}
