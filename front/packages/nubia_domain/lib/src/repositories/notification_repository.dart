import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/app_notification.dart';
import 'package:nubia_domain/src/entities/notification_preferences.dart';

abstract class NotificationRepository {
  /// Returns notifications sorted by [AppNotification.createdAt] descending.
  Future<Either<Failure, List<AppNotification>>> getNotifications();

  /// Marks a single notification as read.
  Future<Either<Failure, void>> markRead(String notificationId);

  /// Marks all notifications as read.
  Future<Either<Failure, void>> markAllRead();

  /// Registers the device FCM token on the backend.
  Future<Either<Failure, void>> registerFcmToken(String token);

  /// Returns the user's notification opt-in preferences.
  Future<Either<Failure, NotificationPreferences>> getPreferences();

  /// Persists updated notification preferences.
  Future<Either<Failure, void>> updatePreferences(
    NotificationPreferences preferences,
  );
}
