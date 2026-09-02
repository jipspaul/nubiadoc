import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_dashboard_repository.dart';

class GetProDashboardSummaryUseCase {
  final CabinetDashboardRepository _repository;

  const GetProDashboardSummaryUseCase(this._repository);

  Future<Either<Failure, ProDashboardSummary>> call({
    String? practitionerId,
  }) =>
      _repository.getSummary(practitionerId: practitionerId);
}
