abstract class UserSettingsRepository {
  Future<bool> getBiometricEnabled();
  Future<void> setBiometricEnabled(bool enabled);
}
