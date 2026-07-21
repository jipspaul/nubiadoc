import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/dental_chart.dart';
import 'package:nubia_domain/src/repositories/dental_chart_repository.dart';

class GetDentalChartUseCase {
  final DentalChartRepository _repository;

  const GetDentalChartUseCase(this._repository);

  Future<Either<Failure, DentalChart>> call(String patientId) =>
      _repository.get(patientId);
}
