import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_record_summary.dart';

abstract class MedicalRecordRepository {
  /// GET /v1/cabinet/patients/{id}/medical-record (#4076).
  Future<Either<Failure, MedicalRecordSummary>> getMedicalRecord(
      String patientId);
}
