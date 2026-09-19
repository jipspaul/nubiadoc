import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_brief.dart';
import 'package:nubia_domain/src/repositories/cabinet_briefs_repository.dart';

class GetCabinetBriefUseCase {
  final CabinetBriefsRepository _repository;

  const GetCabinetBriefUseCase(this._repository);

  Future<Either<Failure, CabinetBrief>> call({
    required String view,
    String? date,
  }) =>
      _repository.fetch(view: view, date: date);
}
