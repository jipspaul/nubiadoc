import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/notifications/notification_api.dart';
import 'package:nubia_data/src/remote/notifications/notification_preferences_dto.dart';
import 'package:nubia_domain/src/entities/app_notification.dart';
import 'package:nubia_domain/src/entities/notification_preferences.dart';
import 'package:nubia_domain/src/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationApi _api;

  const NotificationRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<AppNotification>>> getNotifications() async {
    try {
      final dtos = await _api.getNotifications();
      final notifications = dtos.map((d) => d.toDomain()).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return Right(notifications);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des notifications.'));
    }
  }

  @override
  Future<Either<Failure, void>> markRead(String notificationId) async {
    try {
      await _api.markRead(notificationId);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du marquage comme lu.'));
    }
  }

  @override
  Future<Either<Failure, void>> markAllRead() async {
    try {
      await _api.markAllRead();
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du marquage de toutes les notifications.'));
    }
  }

  @override
  Future<Either<Failure, void>> registerFcmToken(String token) async {
    try {
      await _api.registerFcmToken(token);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de l\'enregistrement du token.'));
    }
  }

  @override
  Future<Either<Failure, NotificationPreferences>> getPreferences() async {
    try {
      final dto = await _api.getPreferences();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des préférences.'));
    }
  }

  @override
  Future<Either<Failure, void>> updatePreferences(
    NotificationPreferences preferences,
  ) async {
    try {
      await _api.updatePreferences(
        NotificationPreferencesDto.fromDomain(preferences),
      );
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de la mise à jour des préférences.'));
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
