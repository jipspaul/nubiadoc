import 'package:equatable/equatable.dart';

/// Résumé de caisse du jour (#5382) — encaissé aujourd'hui, reste à
/// encaisser avant la fermeture, impayés du cabinet. Source :
/// `GET /v1/cabinet/cash-collection/today`.
class CashCollectionSummary extends Equatable {
  final int collectedTodayCents;
  final int collectedTodayPaymentCount;
  final int remainingTodayCents;
  final int remainingTodayPatientCount;
  final int closingHour;
  final int unpaidCents;
  final int unpaidPatientCount;

  const CashCollectionSummary({
    required this.collectedTodayCents,
    required this.collectedTodayPaymentCount,
    required this.remainingTodayCents,
    required this.remainingTodayPatientCount,
    required this.closingHour,
    required this.unpaidCents,
    required this.unpaidPatientCount,
  });

  @override
  List<Object?> get props => [
        collectedTodayCents,
        collectedTodayPaymentCount,
        remainingTodayCents,
        remainingTodayPatientCount,
        closingHour,
        unpaidCents,
        unpaidPatientCount,
      ];
}
