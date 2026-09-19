import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';
import 'package:nubia_domain/src/repositories/cabinet_correspondents_repository.dart';

class GetCorrespondentStatsUseCase {
  final CabinetCorrespondentsRepository _repository;

  const GetCorrespondentStatsUseCase(this._repository);

  Future<Either<Failure, CorrespondentStats>> call(String id) =>
      _repository.getStats(id);
}
