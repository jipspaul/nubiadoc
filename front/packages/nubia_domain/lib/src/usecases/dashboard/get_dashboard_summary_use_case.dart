import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/dashboard_repository.dart';

class GetDashboardSummaryUseCase {
  final DashboardRepository _repository;

  const GetDashboardSummaryUseCase(this._repository);

  Future<Either<Failure, DashboardSummary>> call() =>
      _repository.getSummary();
}
