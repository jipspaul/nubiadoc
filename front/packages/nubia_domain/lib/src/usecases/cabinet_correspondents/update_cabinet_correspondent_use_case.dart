import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';
import 'package:nubia_domain/src/repositories/cabinet_correspondents_repository.dart';

class UpdateCabinetCorrespondentUseCase {
  final CabinetCorrespondentsRepository _repository;

  const UpdateCabinetCorrespondentUseCase(this._repository);

  Future<Either<Failure, CabinetCorrespondent>> call(
    String id, {
    String? displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) =>
      _repository.update(
        id,
        displayName: displayName,
        specialty: specialty,
        email: email,
        phone: phone,
        address: address,
        rpps: rpps,
        notes: notes,
      );
}
