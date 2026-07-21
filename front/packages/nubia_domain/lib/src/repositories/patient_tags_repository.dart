import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_tag.dart';

abstract class PatientTagsRepository {
  Future<Either<Failure, List<PatientTag>>> list(String patientId);

  Future<Either<Failure, PatientTag>> create(
    String patientId, {
    required String label,
    String? color,
  });

  Future<Either<Failure, void>> delete(String patientId, String tagId);
}
