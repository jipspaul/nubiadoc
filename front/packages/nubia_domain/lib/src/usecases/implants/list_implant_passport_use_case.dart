import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/implant_item.dart';
import 'package:nubia_domain/src/repositories/implant_passport_repository.dart';

class ListImplantPassportUseCase {
  final ImplantPassportRepository _repository;

  const ListImplantPassportUseCase(this._repository);

  Future<Either<Failure, List<ImplantItem>>> call() =>
      _repository.listPassport();
}
