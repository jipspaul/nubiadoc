import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pro_notification_preferences.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class ProNotificationPreferencesRepository {
  /// Returns the current user's pro notification preferences
  /// (`GET /v1/me/notification-preferences`).
  Future<Either<Failure, ProNotificationPreferences>> getPreferences();

  /// Persists updated preferences (`PATCH /v1/me/notification-preferences`).
  Future<Either<Failure, ProNotificationPreferences>> updatePreferences(
    ProNotificationPreferences preferences,
  );
}
