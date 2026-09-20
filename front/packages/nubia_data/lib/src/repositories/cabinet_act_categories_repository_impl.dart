import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_data/src/remote/cabinet_info/cabinet_act_categories_api.dart';

class CabinetActCategoriesRepositoryImpl
    implements CabinetActCategoriesRepository {
  final CabinetActCategoriesApi _api;

  const CabinetActCategoriesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ActCategorySetting>>> getActCategories() async {
    try {
      final data = await _api.getActCategories();
      return Right(_toEntities(data));
    } on DioException catch (e) {
      return Left(_failureFor(e));
    } catch (_) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<ActCategorySetting>>> updateActCategories(
    List<ActCategorySetting> categories,
  ) async {
    try {
      final data = await _api.updateActCategories([
        for (final c in categories) (category: c.category, enabled: c.enabled),
      ]);
      return Right(_toEntities(data));
    } on DioException catch (e) {
      return Left(_failureFor(e));
    } catch (_) {
      return const Left(ParseFailure());
    }
  }

  List<ActCategorySetting> _toEntities(
    List<({String category, bool enabled})> data,
  ) =>
      data
          .map((e) =>
              ActCategorySetting(category: e.category, enabled: e.enabled))
          .toList();

  Failure _failureFor(DioException e) {
    if (e.response?.statusCode == 401) {
      return const UnauthorizedFailure();
    }
    if (e.response?.statusCode == 403) {
      return const ServerFailure(
        message: 'Accès refusé. Rôle administrateur requis.',
        statusCode: 403,
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure();
    }
    return ServerFailure(
      message: 'Erreur lors de la mise à jour des catégories d\'actes.',
      statusCode: e.response?.statusCode,
    );
  }
}
