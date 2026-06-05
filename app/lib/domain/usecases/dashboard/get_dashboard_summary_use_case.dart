import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';

@injectable
class GetDashboardSummaryUseCase {
  final DashboardRepository _repository;

  const GetDashboardSummaryUseCase(this._repository);

  Future<Either<Failure, DashboardSummary>> call() =>
      _repository.getSummary();
}
