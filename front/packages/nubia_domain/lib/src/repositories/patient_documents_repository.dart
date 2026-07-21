import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_document.dart';

abstract class PatientDocumentsRepository {
  Future<Either<Failure, List<PatientDocument>>> list(
    String patientId, {
    String? category,
  });
}
