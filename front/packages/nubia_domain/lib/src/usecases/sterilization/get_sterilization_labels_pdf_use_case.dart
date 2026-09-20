import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/sterilization_repository.dart';

class GetSterilizationLabelsPdfUseCase {
  final SterilizationRepository _repository;

  const GetSterilizationLabelsPdfUseCase(this._repository);

  Future<Either<Failure, List<int>>> call(
    String cycleId, {
    int? shelfLifeDays,
  }) =>
      _repository.fetchLabelsPdf(cycleId, shelfLifeDays: shelfLifeDays);
}
