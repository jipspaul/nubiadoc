import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/patient_alerts/patient_alerts_api.dart';
import 'package:nubia_domain/src/entities/patient_alert.dart';
import 'package:nubia_domain/src/repositories/patient_alerts_repository.dart';

class PatientAlertsRepositoryImpl implements PatientAlertsRepository {
  final PatientAlertsApi _api;

  const PatientAlertsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<PatientAlert>>> list(String patientId) async {
    try {
      final dtos = await _api.list(patientId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger les alertes du patient.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
