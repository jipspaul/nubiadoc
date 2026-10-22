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
  Future<Either<Failure, List<AppNotification>>> getNotifications({
    bool unreadOnly = false,
  }) async {
    try {
      final dtos = await _api.getNotifications(unreadOnly: unreadOnly);
      final notifications = dtos.map((d) => d.toDomain()).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return Right(notifications);
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement des notifications.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, PagedNotifications>> getPage({
    int limit = 20,
    String? cursor,
    bool unreadOnly = false,
    NotificationType? type,
  }) async {
    try {
      final page = await _api.getPage(
        limit: limit,
        cursor: cursor,
        unreadOnly: unreadOnly,
        type: type == null ? null : _apiTypeCodeFor(type),
      );
      return Right((
        notifications: page.notifications.map((d) => d.toDomain()).toList(),
        nextCursor: page.nextCursor,
        total: page.total,
      ));
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement des notifications.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, int>> getUnreadCount() async {
    try {
      final count = await _api.getUnreadCount();
      return Right(count);
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement du compteur non-lus.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, Map<NotificationType, int>>> typeCounts() async {
    try {
      final counted = await Future.wait(_typeApiCodes.map((entry) async {
        final total = await _api.count(type: entry.$1);
        return (entry.$2, total);
      }));
      final counts = <NotificationType, int>{};
      for (final (type, total) in counted) {
        counts[type] = total;
      }
      return Right(counts);
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement des compteurs.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  /// Familles interrogées par [typeCounts] — les 3 seules utilisées par les
  /// puces de facette de l'écran Notifications (#8342) ; `message`/`other`
  /// n'ont pas de puce dédiée, inutile de les compter côté serveur.
  static const _typeApiCodes = <(String, NotificationType)>[
    ('appointment', NotificationType.appointment),
    ('document', NotificationType.document),
    ('payment', NotificationType.payment),
  ];

  /// Traduit une famille domaine vers le code `?type=` attendu par
  /// `api/src/notifications.rs::type_filter_sql` (#8357) — même table que
  /// [_typeApiCodes], utilisée ici par [getPage] plutôt que par
  /// [typeCounts].
  static String? _apiTypeCodeFor(NotificationType type) {
    for (final (code, candidate) in _typeApiCodes) {
      if (candidate == type) return code;
    }
    return null;
  }

  @override
  Future<Either<Failure, void>> markRead(String notificationId) async {
    try {
      await _api.markRead(notificationId);
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du marquage comme lu.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> markAllRead() async {
    try {
      await _api.markAllRead();
      return const Right(null);
    } on DioException catch (e) {
      return Left(_mapDioError(
          e, 'Erreur lors du marquage de toutes les notifications.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _api.registerDevice(fcmToken: fcmToken, platform: platform);
      return const Right(null);
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors de l\'enregistrement du device.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> unregisterFcmToken(String token) async {
    try {
      await _api.unregisterDevice(token);
      return const Right(null);
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du désenregistrement du device.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, NotificationPreferences>> getPreferences() async {
    try {
      final dto = await _api.getPreferences();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(
          _mapDioError(e, 'Erreur lors du chargement des préférences.'));
    } catch (e) {
      return const Left(ParseFailure());
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
