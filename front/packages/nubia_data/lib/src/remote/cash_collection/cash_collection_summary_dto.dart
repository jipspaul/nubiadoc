import 'package:nubia_domain/src/entities/cash_collection_summary.dart';

class CashCollectionSummaryDto {
  final int collectedTodayCents;
  final int collectedTodayPaymentCount;
  final int remainingTodayCents;
  final int remainingTodayPatientCount;
  final int closingHour;
  final int unpaidCents;
  final int unpaidPatientCount;

  const CashCollectionSummaryDto({
    required this.collectedTodayCents,
    required this.collectedTodayPaymentCount,
    required this.remainingTodayCents,
    required this.remainingTodayPatientCount,
    required this.closingHour,
    required this.unpaidCents,
    required this.unpaidPatientCount,
  });

  factory CashCollectionSummaryDto.fromJson(Map<String, dynamic> json) =>
      CashCollectionSummaryDto(
        collectedTodayCents: json['collected_today_cents'] as int,
        collectedTodayPaymentCount:
            json['collected_today_payment_count'] as int,
        remainingTodayCents: json['remaining_today_cents'] as int,
        remainingTodayPatientCount:
            json['remaining_today_patient_count'] as int,
        closingHour: json['closing_hour'] as int,
        unpaidCents: json['unpaid_cents'] as int,
        unpaidPatientCount: json['unpaid_patient_count'] as int,
      );

  CashCollectionSummary toDomain() => CashCollectionSummary(
        collectedTodayCents: collectedTodayCents,
        collectedTodayPaymentCount: collectedTodayPaymentCount,
        remainingTodayCents: remainingTodayCents,
        remainingTodayPatientCount: remainingTodayPatientCount,
        closingHour: closingHour,
        unpaidCents: unpaidCents,
        unpaidPatientCount: unpaidPatientCount,
      );
}
