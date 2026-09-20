import 'package:nubia_domain/src/entities/treatment_session.dart';

class TreatmentSessionDto {
  final String id;
  final int position;
  final int durationMin;
  final List<String> quoteItemIds;

  const TreatmentSessionDto({
    required this.id,
    required this.position,
    required this.durationMin,
    required this.quoteItemIds,
  });

  factory TreatmentSessionDto.fromJson(Map<String, dynamic> json) =>
      TreatmentSessionDto(
        id: json['session_id'] as String,
        position: json['position'] as int,
        durationMin: json['duration_min'] as int,
        quoteItemIds: (json['quote_item_ids'] as List<dynamic>? ?? const [])
            .map((id) => id as String)
            .toList(),
      );

  /// Séance fraîchement proposée — toujours `planned` (`POST .../propose`
  /// persiste les nouvelles séances sous ce statut, #7173).
  TreatmentSession toDomain() => TreatmentSession(
        id: id,
        position: position,
        durationMin: durationMin,
        quoteItemIds: quoteItemIds,
        status: 'planned',
      );
}

class ProposedSlotDto {
  final String id;
  final String practitionerId;
  final String startsAt;
  final String endsAt;

  const ProposedSlotDto({
    required this.id,
    required this.practitionerId,
    required this.startsAt,
    required this.endsAt,
  });

  factory ProposedSlotDto.fromJson(Map<String, dynamic> json) =>
      ProposedSlotDto(
        id: json['slot_id'] as String,
        practitionerId: json['practitioner_id'] as String,
        startsAt: json['starts_at'] as String,
        endsAt: json['ends_at'] as String,
      );

  ProposedSlot toDomain() => ProposedSlot(
        id: id,
        practitionerId: practitionerId,
        startsAt: DateTime.parse(startsAt),
        endsAt: DateTime.parse(endsAt),
      );
}
