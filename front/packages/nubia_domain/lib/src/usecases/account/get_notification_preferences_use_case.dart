import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/notification_preferences.dart';
import 'package:nubia_domain/src/repositories/notification_repository.dart';

class GetNotificationPreferencesUseCase {
  final NotificationRepository _repository;

  const GetNotificationPreferencesUseCase(this._repository);

  Future<Either<Failure, NotificationPreferences>> call() {
    return _repository.getPreferences();
  }
}
