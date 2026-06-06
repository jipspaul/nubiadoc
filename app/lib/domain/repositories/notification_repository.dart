import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/app_notification.dart';

abstract class NotificationRepository {
  /// Returns notifications sorted by [AppNotification.createdAt] descending.
  Future<Either<Failure, List<AppNotification>>> getNotifications();

  /// Marks a single notification as read.
  Future<Either<Failure, void>> markRead(String notificationId);

  /// Marks all notifications as read.
  Future<Either<Failure, void>> markAllRead();

  /// Registers the device FCM token on the backend.
  Future<Either<Failure, void>> registerFcmToken(String token);
}
