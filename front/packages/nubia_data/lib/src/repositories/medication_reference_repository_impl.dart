import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/prescriptions/prescription_api.dart';
import 'package:nubia_domain/src/entities/medication_reference.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/medication_reference_repository.dart';

class MedicationReferenceRepositoryImpl
    implements MedicationReferenceRepository {
  final PrescriptionApi _api;

  const MedicationReferenceRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<MedicationReference>>>
      searchMedicationReferences({required String query}) async {
    try {
      final dtos = await _api.searchMedicationReferences(query);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Référentiel indisponible.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
