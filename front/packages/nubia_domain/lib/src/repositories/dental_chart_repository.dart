import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/dental_chart.dart';

abstract class DentalChartRepository {
  Future<Either<Failure, DentalChart>> get(String patientId);

  /// Remplacement atomique (PUT) — `teeth` complet, pas un patch partiel.
  Future<Either<Failure, DentalChart>> put(
    String patientId,
    Map<String, ToothState> teeth,
  );
}
