import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

class ApplyPrescriptionTemplateUseCase {
  final PrescriptionRepository _repository;

  const ApplyPrescriptionTemplateUseCase(this._repository);

  Future<Either<Failure, Prescription>> call({
    required String prescriptionId,
    required String templateId,
  }) =>
      _repository.applyPrescriptionTemplate(
        prescriptionId: prescriptionId,
        templateId: templateId,
      );
}
