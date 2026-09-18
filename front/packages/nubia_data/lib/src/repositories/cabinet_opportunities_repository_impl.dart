import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_opportunities/cabinet_opportunities_api.dart';
import 'package:nubia_domain/src/entities/opportunity_category.dart';
import 'package:nubia_domain/src/repositories/cabinet_opportunities_repository.dart';

class CabinetOpportunitiesRepositoryImpl
    implements CabinetOpportunitiesRepository {
  final CabinetOpportunitiesApi _api;

  const CabinetOpportunitiesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<OpportunityCategory>>> getOpportunities() async {
    try {
      final dtos = await _api.getOpportunities();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les opportunités du cabinet.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
