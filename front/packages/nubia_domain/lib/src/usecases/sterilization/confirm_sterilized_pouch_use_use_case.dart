import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/sterilized_pouch_use.dart';
import 'package:nubia_domain/src/repositories/sterilization_repository.dart';

/// Scan du QR d'une étiquette de sachet stérilisé pendant la consultation
/// (#7180), pour tracer son ouverture sur le patient (et la séance) en
/// cours.
class ConfirmSterilizedPouchUseUseCase {
  final SterilizationRepository _repository;

  const ConfirmSterilizedPouchUseUseCase(this._repository);

  Future<Either<Failure, SterilizedPouchUse>> call(
    String code, {
    required String patientId,
    String? consultationId,
  }) =>
      _repository.usePouch(
        code,
        patientId: patientId,
        consultationId: consultationId,
      );
}
