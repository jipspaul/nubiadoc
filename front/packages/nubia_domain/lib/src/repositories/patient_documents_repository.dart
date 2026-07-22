import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_document.dart';

abstract class PatientDocumentsRepository {
  Future<Either<Failure, List<PatientDocument>>> list(
    String patientId, {
    String? category,
  });

  /// POST /v1/cabinet/patients/:id/documents (#4133). Renvoie l'id du
  /// document créé.
  Future<Either<Failure, String>> upload(
    String patientId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required String category,
  });
}
