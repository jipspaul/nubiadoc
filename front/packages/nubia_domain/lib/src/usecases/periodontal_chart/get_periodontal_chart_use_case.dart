import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/periodontal_chart.dart';
import 'package:nubia_domain/src/repositories/periodontal_chart_repository.dart';

class GetPeriodontalChartUseCase {
  final PeriodontalChartRepository _repository;

  const GetPeriodontalChartUseCase(this._repository);

  Future<Either<Failure, PeriodontalChart>> call(String patientId) =>
      _repository.get(patientId);
}
