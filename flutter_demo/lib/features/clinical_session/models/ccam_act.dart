import 'package:equatable/equatable.dart';

/// Acte CCAM réalisé pendant une séance clinique.
///
/// Contrat POST /v1/cabinet/consultations/{id}/acts
/// body : { ccam_code, label, tooth?, amount_cents?, included?:bool }
class CcamAct extends Equatable {
  const CcamAct({
    required this.id,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  final String id;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  @override
  List<Object?> get props => [id, ccamCode, label, tooth, amountCents, included];
}
