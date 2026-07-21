import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/periodontal_chart.dart';
import 'package:nubia_domain/src/repositories/periodontal_chart_repository.dart';

class PutPeriodontalChartUseCase {
  final PeriodontalChartRepository _repository;

  const PutPeriodontalChartUseCase(this._repository);

  Future<Either<Failure, PeriodontalChart>> call(
    String patientId,
    Map<String, ToothSiteDepths> sites,
    Map<String, double> indices,
  ) =>
      _repository.put(patientId, sites, indices);
}
