import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/custom_device_declaration_result.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/compliance_repository.dart';

/// Déclare un dispositif médical sur mesure (DMSM) depuis la fiche patient
/// (#7170) — `POST /v1/patients/:id/custom-device-declarations`.
class DeclareCustomDeviceUseCase {
  final ComplianceRepository _repository;

  const DeclareCustomDeviceUseCase(this._repository);

  Future<Either<Failure, CustomDeviceDeclarationResult>> call({
    required String patientId,
    required String labName,
    required String deviceDescription,
    String? consultationActId,
  }) =>
      _repository.declareCustomDevice(
        patientId: patientId,
        labName: labName,
        deviceDescription: deviceDescription,
        consultationActId: consultationActId,
      );
}
