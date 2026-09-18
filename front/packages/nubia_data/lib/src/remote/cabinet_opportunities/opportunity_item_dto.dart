import 'package:nubia_domain/src/entities/opportunity_category.dart';

class OpportunityItemDto {
  final String kind;
  final String patientId;
  final String? patientName;
  final int? amountCents;
  final int? sinceDays;
  final String? quoteId;

  const OpportunityItemDto({
    required this.kind,
    required this.patientId,
    this.patientName,
    this.amountCents,
    this.sinceDays,
    this.quoteId,
  });

  factory OpportunityItemDto.fromJson(Map<String, dynamic> json) =>
      OpportunityItemDto(
        kind: json['kind'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String?,
        amountCents: json['amount_cents'] as int?,
        sinceDays: json['since_days'] as int?,
        quoteId: json['quote_id'] as String?,
      );

  OpportunityItem toDomain() => OpportunityItem(
        kind: kind,
        patientId: patientId,
        patientName: patientName,
        amountCents: amountCents,
        sinceDays: sinceDays,
        quoteId: quoteId,
      );
}
