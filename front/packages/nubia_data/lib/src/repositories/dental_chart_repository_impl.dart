import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/dental_chart/dental_chart_api.dart';
import 'package:nubia_data/src/remote/dental_chart/dental_chart_dto.dart';
import 'package:nubia_domain/src/entities/dental_chart.dart';
import 'package:nubia_domain/src/repositories/dental_chart_repository.dart';

class DentalChartRepositoryImpl implements DentalChartRepository {
  final DentalChartApi _api;

  const DentalChartRepositoryImpl(this._api);

  @override
  Future<Either<Failure, DentalChart>> get(String patientId) async {
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
        message: "Impossible de charger le schéma dentaire.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, DentalChart>> put(
    String patientId,
    Map<String, ToothState> teeth,
  ) async {
    try {
      final dto = DentalChartDto(
        teeth: teeth.map(
          (k, v) => MapEntry(k, ToothStateDto.fromDomain(v)),
        ),
        updatedAt: DateTime.now().toIso8601String(),
      );
      final response = await _api.put(patientId, dto);
      return Right(response.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Schéma dentaire invalide.'),
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
        message: "Impossible d'enregistrer le schéma dentaire.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
