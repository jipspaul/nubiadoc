import 'package:nubia_domain/src/entities/treatment_plan.dart';

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

class TreatmentPhaseDto {
  final String id;
  final int position;
  final String title;
  final String status;
  final TreatmentPhaseQuoteRefDto? quoteRef;

  const TreatmentPhaseDto({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.quoteRef,
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
    );
  }

  TreatmentPhase toDomain() => TreatmentPhase(
        id: id,
        position: position,
        title: title,
        status: status,
        quoteRef: quoteRef?.toDomain(),
      );
}

class TreatmentPlanDto {
  final String id;
  final String title;
  final String status;
  final String createdAt;
  final List<TreatmentPhaseDto> phases;

  const TreatmentPlanDto({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.phases,
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
      );

  TreatmentPlan toDomain() => TreatmentPlan(
        id: id,
        title: title,
        status: status,
        createdAt: DateTime.parse(createdAt),
        phases: phases.map((p) => p.toDomain()).toList(),
      );
}
