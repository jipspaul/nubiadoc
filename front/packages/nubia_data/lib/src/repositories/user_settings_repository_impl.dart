import 'package:nubia_domain/nubia_domain.dart';

class InMemoryUserSettingsRepository implements UserSettingsRepository {
  bool _biometricEnabled = false;

  @override
  Future<bool> getBiometricEnabled() async => _biometricEnabled;

  @override
  Future<void> setBiometricEnabled(bool enabled) async {
    _biometricEnabled = enabled;
  }
}
