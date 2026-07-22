import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/implant_passport_repository.dart';

class ExportImplantPassportUseCase {
  final ImplantPassportRepository _repository;

  const ExportImplantPassportUseCase(this._repository);

  Future<Either<Failure, String>> call() => _repository.exportPassport();
}
