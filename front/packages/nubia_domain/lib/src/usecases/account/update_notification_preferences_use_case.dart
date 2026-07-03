import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/notification_preferences.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/notification_repository.dart';

class UpdateNotificationPreferencesUseCase {
  final NotificationRepository _repository;
  const UpdateNotificationPreferencesUseCase(this._repository);

  Future<Either<Failure, void>> call(NotificationPreferences preferences) =>
      _repository.updatePreferences(preferences);
}
