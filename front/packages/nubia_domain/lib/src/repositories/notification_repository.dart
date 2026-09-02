import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/app_notification.dart';
import 'package:nubia_domain/src/entities/notification_preferences.dart';

abstract class NotificationRepository {
  /// Returns notifications sorted by [AppNotification.createdAt] descending.
  ///
  /// [unreadOnly] maps to `GET /v1/notifications?unread_only=true` — used by
  /// the pro shell's bell badge (#6263) to poll the unread count without
  /// fetching the (heavier) full list.
  Future<Either<Failure, List<AppNotification>>> getNotifications({
    bool unreadOnly = false,
  });

  /// Marks a single notification as read.
  Future<Either<Failure, void>> markRead(String notificationId);

  /// Marks all notifications as read.
  Future<Either<Failure, void>> markAllRead();

  /// Registers the device with the backend via `POST /v1/devices`.
  Future<Either<Failure, void>> registerDevice({
    required String fcmToken,
    required String platform,
  });

  /// Deregisters the device FCM token on the backend (called on logout).
  Future<Either<Failure, void>> unregisterFcmToken(String token);

  /// Returns the user's notification opt-in preferences.
  Future<Either<Failure, NotificationPreferences>> getPreferences();

  /// Persists updated notification preferences.
  Future<Either<Failure, void>> updatePreferences(
    NotificationPreferences preferences,
  );
}
