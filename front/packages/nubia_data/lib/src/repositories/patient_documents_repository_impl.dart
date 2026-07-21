import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/patient_documents/patient_documents_api.dart';
import 'package:nubia_domain/src/entities/patient_document.dart';
import 'package:nubia_domain/src/repositories/patient_documents_repository.dart';

class PatientDocumentsRepositoryImpl implements PatientDocumentsRepository {
  final PatientDocumentsApi _api;

  const PatientDocumentsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<PatientDocument>>> list(
    String patientId, {
    String? category,
  }) async {
    try {
      final dtos = await _api.list(patientId, category: category);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les documents.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
