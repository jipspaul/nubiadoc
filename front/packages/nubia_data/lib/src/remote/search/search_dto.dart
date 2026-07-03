import 'package:nubia_domain/src/entities/provider_result.dart';
import 'package:nubia_domain/src/entities/slot.dart';

class ProviderResultDto {
  final String id;
  final String displayName;
  final String specialty;
  final double? distanceKm;
  final double? lat;
  final double? lng;
  final double? ratingAvg;
  final String? nextSlotAt;

  const ProviderResultDto({
    required this.id,
    required this.displayName,
    required this.specialty,
    this.distanceKm,
    this.lat,
    this.lng,
    this.ratingAvg,
    this.nextSlotAt,
  });

  /// Contrat réel : ProviderItem (api/src/marketplace.rs) — clé `provider_id`,
  /// distance en mètres, `geo` = GeoJSON Point {coordinates:[lng,lat]}.
  factory ProviderResultDto.fromJson(Map<String, dynamic> json) {
    double? lat;
    double? lng;
    // Contrat réel : geo = {lat, lng} (api/src/marketplace.rs), pas du GeoJSON.
    final geo = json['geo'];
    if (geo is Map) {
      lat = (geo['lat'] as num?)?.toDouble();
      lng = (geo['lng'] as num?)?.toDouble();
    }
    final distanceM = (json['distance_m'] as num?)?.toDouble();
    return ProviderResultDto(
      id: json['provider_id'] as String,
      displayName: json['display_name'] as String,
      specialty: (json['specialty'] as String?) ?? 'Praticien',
      distanceKm: distanceM == null ? null : distanceM / 1000,
      lat: lat,
      lng: lng,
      ratingAvg: (json['rating_avg'] as num?)?.toDouble(),
      nextSlotAt: json['next_slot_at'] as String?,
    );
  }

  ProviderResult toDomain() => ProviderResult(
        id: id,
        displayName: displayName,
        specialty: specialty,
        distanceKm: distanceKm,
        lat: lat,
        lng: lng,
        ratingAvg: ratingAvg,
        nextSlotAt: nextSlotAt == null ? null : DateTime.tryParse(nextSlotAt!),
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

  /// GET /v1/providers/:id/availability → AvailabilitySlotItem :
  /// {slot_id, starts_at, ends_at, motif?}. Pas de cabinet/practitioner id
  /// (non requis pour le hold/booking, qui ne prennent que le slot_id).
  factory SlotDto.fromAvailabilityJson(Map<String, dynamic> json) => SlotDto(
        id: json['slot_id'] as String,
        cabinetId: '',
        practitionerId: '',
        startsAt: json['starts_at'] as String,
        endsAt: json['ends_at'] as String,
        isAvailable: true,
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
