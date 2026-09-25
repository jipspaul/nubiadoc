import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_vcard_repository.dart';

class GetCabinetVcardUseCase {
  final CabinetVcardRepository _repository;

  const GetCabinetVcardUseCase(this._repository);

  Future<Either<Failure, List<int>>> call() => _repository.fetchVcard();
}
