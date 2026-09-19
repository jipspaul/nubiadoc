import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_briefs_repository.dart';

class GetCabinetBriefPdfUseCase {
  final CabinetBriefsRepository _repository;

  const GetCabinetBriefPdfUseCase(this._repository);

  Future<Either<Failure, List<int>>> call({
    required String view,
    String? date,
  }) =>
      _repository.fetchPdf(view: view, date: date);
}
