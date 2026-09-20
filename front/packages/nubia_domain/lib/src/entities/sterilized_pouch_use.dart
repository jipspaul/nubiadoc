import 'package:equatable/equatable.dart';

/// Résultat de `POST /v1/sterilization/pouches/:code/use` (#7181/#7180) —
/// rattachement d'un sachet stérilisé (déjà enregistré/étiqueté) à un
/// patient, et optionnellement à une séance de consultation, par scan du QR
/// de l'étiquette.
class SterilizedPouchUse extends Equatable {
  final String pouchId;
  final String code;
  final String cycleId;
  final String patientId;
  final String? consultationId;
  final DateTime usedAt;

  /// `true` si le sachet était déjà rattaché à ce patient (rejeu
  /// idempotent), `false` au premier scan.
  final bool alreadyUsed;

  const SterilizedPouchUse({
    required this.pouchId,
    required this.code,
    required this.cycleId,
    required this.patientId,
    this.consultationId,
    required this.usedAt,
    required this.alreadyUsed,
  });

  @override
  List<Object?> get props =>
      [pouchId, code, cycleId, patientId, consultationId, usedAt, alreadyUsed];
}
