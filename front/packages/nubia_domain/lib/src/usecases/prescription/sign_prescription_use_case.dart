import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

class SignPrescriptionUseCase {
  final PrescriptionRepository _repository;

  const SignPrescriptionUseCase(this._repository);

  Future<Either<Failure, Prescription>> call(String prescriptionId) =>
      _repository.signPrescription(prescriptionId);
}
