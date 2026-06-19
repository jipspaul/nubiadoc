import 'package:nubia_domain/src/entities/slot.dart';

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
        isAvailable: (json['is_available'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'practitioner_id': practitionerId,
        'starts_at': startsAt,
        'ends_at': endsAt,
        'is_available': isAvailable,
      };

  Slot toDomain() => Slot(
        id: id,
        cabinetId: cabinetId,
        practitionerId: practitionerId,
        startsAt: DateTime.parse(startsAt),
        endsAt: DateTime.parse(endsAt),
        isAvailable: isAvailable,
      );
}
