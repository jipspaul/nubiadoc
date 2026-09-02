import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_data/src/remote/notifications/notification_api.dart';
import 'package:nubia_data/src/remote/notifications/pro_notification_preferences_dto.dart';
import 'package:nubia_domain/src/entities/pro_notification_preferences.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pro_notification_preferences_repository.dart';

class ProNotificationPreferencesRepositoryImpl
    implements ProNotificationPreferencesRepository {
  final NotificationApi _api;

  const ProNotificationPreferencesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, ProNotificationPreferences>> getPreferences() async {
    try {
      final dto = await _api.getMePreferences();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement des préférences.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ProNotificationPreferences>> updatePreferences(
    ProNotificationPreferences preferences,
  ) async {
    try {
      final dto = await _api.updateMePreferences(
        ProNotificationPreferencesDto.fromDomain(preferences),
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors de la mise à jour des préférences.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapDioError(DioException e, String defaultMessage) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const OfflineFailure();
    }
    if (e.response?.statusCode == 401) {
      return const UnauthorizedFailure();
    }
    return ServerFailure(
      message: defaultMessage,
      statusCode: e.response?.statusCode,
    );
  }
}
