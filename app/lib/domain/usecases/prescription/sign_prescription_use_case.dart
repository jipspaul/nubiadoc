import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';
import 'package:nubia_patient/domain/repositories/prescription_repository.dart';

@injectable
class SignPrescriptionUseCase {
  final PrescriptionRepository _repository;

  const SignPrescriptionUseCase(this._repository);

  Future<Either<Failure, Prescription>> call(String prescriptionId) =>
      _repository.signPrescription(prescriptionId);
}
