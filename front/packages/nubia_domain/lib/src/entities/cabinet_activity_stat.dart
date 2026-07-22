import 'package:equatable/equatable.dart';

/// Une ligne d'activité cabinet (praticien × acte CCAM), #4153. Source :
/// `GET /v1/cabinet/stats/activity`.
class CabinetActivityStat extends Equatable {
  final String practitionerId;
  final String? practitionerName;
  final String ccamCode;
  final String label;
  final int actCount;
  final int totalAmountCents;

  const CabinetActivityStat({
    required this.practitionerId,
    this.practitionerName,
    required this.ccamCode,
    required this.label,
    required this.actCount,
    required this.totalAmountCents,
  });

  @override
  List<Object?> get props => [practitionerId, ccamCode];
}
