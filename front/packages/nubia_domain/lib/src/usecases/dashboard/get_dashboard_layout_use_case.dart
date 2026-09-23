import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/dashboard_layout_repository.dart';

class GetDashboardLayoutUseCase {
  final DashboardLayoutRepository _repository;

  const GetDashboardLayoutUseCase(this._repository);

  Future<Either<Failure, List<String>>> call() {
    return _repository.getLayout();
  }
}
