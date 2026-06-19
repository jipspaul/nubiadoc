import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/notification_repository.dart';

/// Registers the current device with the backend via `POST /v1/devices`.
class RegisterDeviceUseCase {
  final NotificationRepository _repository;
  const RegisterDeviceUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String fcmToken,
    required String platform,
  }) {
    return _repository.registerDevice(fcmToken: fcmToken, platform: platform);
  }
}
