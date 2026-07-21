import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/periodontal_chart/periodontal_chart_api.dart';
import 'package:nubia_data/src/remote/periodontal_chart/periodontal_chart_dto.dart';
import 'package:nubia_domain/src/entities/periodontal_chart.dart';
import 'package:nubia_domain/src/repositories/periodontal_chart_repository.dart';

class PeriodontalChartRepositoryImpl implements PeriodontalChartRepository {
  final PeriodontalChartApi _api;

  const PeriodontalChartRepositoryImpl(this._api);

  @override
  Future<Either<Failure, PeriodontalChart>> get(String patientId) async {
    try {
      final dto = await _api.get(patientId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return const Left(ClinicalAccessDenied());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le bilan parodontal.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PeriodontalChart>> put(
    String patientId,
    Map<String, ToothSiteDepths> sites,
    Map<String, double> indices,
  ) async {
    try {
      final dto = PeriodontalChartDto(
        sites: sites.map(
          (k, v) => MapEntry(k, ToothSiteDepthsDto.fromDomain(v)),
        ),
        indices: indices,
        measuredAt: DateTime.now().toIso8601String(),
      );
      final response = await _api.put(patientId, dto);
      return Right(response.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Bilan parodontal invalide.'),
        );
      }
      if (e.response?.statusCode == 403) {
        return const Left(ClinicalAccessDenied());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer le bilan parodontal.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
