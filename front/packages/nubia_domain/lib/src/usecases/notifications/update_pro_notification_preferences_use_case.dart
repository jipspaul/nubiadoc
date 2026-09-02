import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pro_notification_preferences.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pro_notification_preferences_repository.dart';

class UpdateProNotificationPreferencesUseCase {
  final ProNotificationPreferencesRepository _repository;

  const UpdateProNotificationPreferencesUseCase(this._repository);

  Future<Either<Failure, ProNotificationPreferences>> call(
    ProNotificationPreferences preferences,
  ) {
    return _repository.updatePreferences(preferences);
  }
}
