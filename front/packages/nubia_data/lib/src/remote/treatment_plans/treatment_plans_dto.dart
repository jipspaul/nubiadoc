import 'package:nubia_domain/src/entities/treatment_plan.dart';
import 'package:nubia_domain/src/entities/treatment_session.dart';

/// Parsing tolérant : `quote_number`/`number` absent → référence ignorée
/// (la phase est traitée comme non couverte par `TreatmentPhaseDto`).
class TreatmentPhaseQuoteRefDto {
  final String quoteNumber;
  final String? signedAt;
  final bool depositPaid;

  const TreatmentPhaseQuoteRefDto({
    required this.quoteNumber,
    this.signedAt,
    this.depositPaid = false,
  });

  factory TreatmentPhaseQuoteRefDto.fromJson(Map<String, dynamic> json) =>
      TreatmentPhaseQuoteRefDto(
        quoteNumber:
            json['quote_number'] as String? ?? json['number'] as String? ?? '',
        signedAt: json['signed_at'] as String?,
        depositPaid: json['deposit_paid'] as bool? ?? false,
      );

  TreatmentPhaseQuoteRef toDomain() => TreatmentPhaseQuoteRef(
        quoteNumber: quoteNumber,
        signedAt: signedAt != null ? DateTime.parse(signedAt!) : null,
        depositPaid: depositPaid,
      );
}

/// Parsing tolérant : chaque champ absent retombe sur une valeur neutre
/// (`amount_cents`/`amountCents` → 0, `label`/`ccam_code`/`tooth`/`subtitle`
/// → vide/nul) plutôt que de faire planter le mapping (#5012).
class TreatmentPhaseActDto {
  final String id;
  final String label;
  final String? ccamCode;
  final String? tooth;
  final int amountCents;
  final String? subtitle;

  const TreatmentPhaseActDto({
    required this.id,
    this.label = '',
    this.ccamCode,
    this.tooth,
    required this.amountCents,
    this.subtitle,
  });

  factory TreatmentPhaseActDto.fromJson(Map<String, dynamic> json) =>
      TreatmentPhaseActDto(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        ccamCode: json['ccam_code'] as String? ?? json['ccamCode'] as String?,
        tooth: json['tooth'] as String?,
        amountCents:
            json['amount_cents'] as int? ?? json['amountCents'] as int? ?? 0,
        subtitle: json['subtitle'] as String?,
      );

  TreatmentPhaseAct toDomain() => TreatmentPhaseAct(
        id: id,
        label: label,
        ccamCode: ccamCode,
        tooth: tooth,
        amountCents: amountCents,
        subtitle: subtitle,
      );
}

class TreatmentPhaseDto {
  final String id;
  final int position;
  final String title;
  final String status;
  final TreatmentPhaseQuoteRefDto? quoteRef;
  final List<TreatmentPhaseActDto> acts;

  const TreatmentPhaseDto({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.quoteRef,
    this.acts = const [],
  });

  factory TreatmentPhaseDto.fromJson(Map<String, dynamic> json) {
    final rawQuoteRef = (json['quote'] ?? json['quote_ref']);
    return TreatmentPhaseDto(
      id: json['id'] as String,
      position: json['position'] as int,
      title: json['title'] as String,
      status: json['status'] as String,
      quoteRef: rawQuoteRef is Map<String, dynamic>
          ? TreatmentPhaseQuoteRefDto.fromJson(rawQuoteRef)
          : null,
      acts: (json['acts'] as List<dynamic>? ?? const [])
          .map((a) => TreatmentPhaseActDto.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  TreatmentPhase toDomain() => TreatmentPhase(
        id: id,
        position: position,
        title: title,
        status: status,
        quoteRef: quoteRef?.toDomain(),
        acts: acts.map((a) => a.toDomain()).toList(),
      );
}

/// Séance imbriquée dans `TreatmentPlanDto` (`GET .../treatment-plans`,
/// #7477) — mêmes séances que celles persistées par `POST
/// .../sessions/propose`, mais rendues avec `id`/`status`/`appointment_id`
/// (clés distinctes de `TreatmentSessionDto`, qui parse la réponse de
/// `propose` sous `session_id` sans `status`/`appointment_id`).
class TreatmentPlanSessionDto {
  final String id;
  final int position;
  final int durationMin;
  final String status;
  final String? appointmentId;
  final List<String> quoteItemIds;

  const TreatmentPlanSessionDto({
    required this.id,
    required this.position,
    required this.durationMin,
    required this.status,
    this.appointmentId,
    required this.quoteItemIds,
  });

  factory TreatmentPlanSessionDto.fromJson(Map<String, dynamic> json) =>
      TreatmentPlanSessionDto(
        id: json['id'] as String,
        position: json['position'] as int,
        durationMin: json['duration_min'] as int,
        status: json['status'] as String,
        appointmentId: json['appointment_id'] as String?,
        quoteItemIds: (json['quote_item_ids'] as List<dynamic>? ?? const [])
            .map((id) => id as String)
            .toList(),
      );

  TreatmentSession toDomain() => TreatmentSession(
        id: id,
        position: position,
        durationMin: durationMin,
        quoteItemIds: quoteItemIds,
        status: status,
        appointmentId: appointmentId,
      );
}

class TreatmentPlanDto {
  final String id;
  final String title;
  final String status;
  final String createdAt;
  final List<TreatmentPhaseDto> phases;
  final List<TreatmentPlanSessionDto> sessions;

  const TreatmentPlanDto({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.phases,
    this.sessions = const [],
  });

  factory TreatmentPlanDto.fromJson(Map<String, dynamic> json) =>
      TreatmentPlanDto(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        createdAt: json['created_at'] as String,
        phases: (json['phases'] as List<dynamic>? ?? const [])
            .map((p) => TreatmentPhaseDto.fromJson(p as Map<String, dynamic>))
            .toList(),
        sessions: (json['sessions'] as List<dynamic>? ?? const [])
            .map((s) =>
                TreatmentPlanSessionDto.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  TreatmentPlan toDomain() => TreatmentPlan(
        id: id,
        title: title,
        status: status,
        createdAt: DateTime.parse(createdAt),
        phases: phases.map((p) => p.toDomain()).toList(),
        sessions: sessions.map((s) => s.toDomain()).toList(),
      );
}
