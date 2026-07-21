import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/dental_chart.dart';
import 'package:nubia_domain/src/repositories/dental_chart_repository.dart';

class PutDentalChartUseCase {
  final DentalChartRepository _repository;

  const PutDentalChartUseCase(this._repository);

  Future<Either<Failure, DentalChart>> call(
    String patientId,
    Map<String, ToothState> teeth,
  ) =>
      _repository.put(patientId, teeth);
}
