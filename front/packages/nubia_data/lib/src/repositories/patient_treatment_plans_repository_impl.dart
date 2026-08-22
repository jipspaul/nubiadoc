import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/patient_treatment_plans/patient_treatment_plans_api.dart';
import 'package:nubia_domain/src/entities/patient_treatment_plan.dart';
import 'package:nubia_domain/src/repositories/patient_treatment_plans_repository.dart';

class PatientTreatmentPlansRepositoryImpl
    implements PatientTreatmentPlansRepository {
  final PatientTreatmentPlansApi _api;

  const PatientTreatmentPlansRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<PatientTreatmentPlan>>> list() async {
    try {
      final dtos = await _api.list();
      // Un patient ne doit jamais voir un plan `draft` (brouillon non
      // finalisé par le praticien) — filtrage à la source, pas au niveau du
      // libellé (#5294). L'API filtre déjà côté serveur ; ce filtre est une
      // défense en profondeur côté repository.
      return Right(
        dtos
            .map((d) => d.toDomain())
            .where((plan) => plan.status != 'draft')
            .toList(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger vos plans de traitement.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PatientTreatmentPlan>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger ce plan de traitement.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
