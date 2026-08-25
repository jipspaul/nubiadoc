import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/implant_passport_repository.dart';

class ExportImplantPassportUseCase {
  final ImplantPassportRepository _repository;

  const ExportImplantPassportUseCase(this._repository);

  /// `implantId` limite l'export à cet implant seul (#5334) — sinon export
  /// du passeport complet (comportement historique, #4142).
  Future<Either<Failure, String>> call({String? implantId}) =>
      _repository.exportPassport(implantId: implantId);
}
