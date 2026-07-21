import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_record_summary.dart';
import 'package:nubia_domain/src/repositories/medical_record_repository.dart';

class GetMedicalRecordUseCase {
  final MedicalRecordRepository _repository;

  const GetMedicalRecordUseCase(this._repository);

  Future<Either<Failure, MedicalRecordSummary>> call(String patientId) =>
      _repository.getMedicalRecord(patientId);
}
