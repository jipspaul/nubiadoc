import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_record_summary.dart';
import 'package:nubia_domain/src/repositories/medical_record_repository.dart';
import '../remote/medical_record/medical_record_api.dart';

class MedicalRecordRepositoryImpl implements MedicalRecordRepository {
  final MedicalRecordApi _api;

  const MedicalRecordRepositoryImpl(this._api);

  @override
  Future<Either<Failure, MedicalRecordSummary>> getMedicalRecord(
      String patientId) async {
    try {
      final dto = await _api.getMedicalRecord(patientId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors du chargement du dossier médical.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
