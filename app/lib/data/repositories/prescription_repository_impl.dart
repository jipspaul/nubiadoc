import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/data/remote/prescriptions/prescription_api.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';
import 'package:nubia_patient/domain/repositories/prescription_repository.dart';

@LazySingleton(as: PrescriptionRepository)
class PrescriptionRepositoryImpl implements PrescriptionRepository {
  final PrescriptionApi _api;

  const PrescriptionRepositoryImpl(this._api);

  @override
  Future<Either<Failure, Prescription>> createPrescription({
    required String patientId,
    required List<PrescriptionItem> items,
  }) async {
    try {
      final dto = await _api.createPrescription(
        patientId: patientId,
        items: items,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de créer l'ordonnance.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Prescription>> signPrescription(String id) async {
    try {
      final dto = await _api.signPrescription(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de signer l'ordonnance.",
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
