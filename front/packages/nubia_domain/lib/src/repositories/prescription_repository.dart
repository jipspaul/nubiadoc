import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription.dart';

abstract class PrescriptionRepository {
  /// POST /v1/cabinet/prescriptions
  Future<Either<Failure, Prescription>> createPrescription({
    required String patientId,
    required List<PrescriptionItem> items,
  });

  /// POST /v1/cabinet/prescriptions/{id}/sign
  Future<Either<Failure, Prescription>> signPrescription(String id);
}
