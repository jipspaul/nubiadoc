import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_repository.dart';

class UpdateCabinetUseCase {
  final CabinetRepository _repository;

  const UpdateCabinetUseCase(this._repository);

  Future<Either<Failure, void>> call(UpdateCabinetRequest request) {
    return _repository.updateCabinet(request);
  }
}
