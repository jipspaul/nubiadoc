import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/sterilization_repository.dart';

class AddSterilizedPouchUseCase {
  final SterilizationRepository _repository;

  const AddSterilizedPouchUseCase(this._repository);

  Future<Either<Failure, String>> call(
    String cycleId, {
    required String code,
    String? consultationActId,
  }) =>
      _repository.addPouch(
        cycleId,
        code: code,
        consultationActId: consultationActId,
      );
}
