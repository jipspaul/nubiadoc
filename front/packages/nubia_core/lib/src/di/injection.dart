import '../storage/kv_store.dart';
import 'package:get_it/get_it.dart';

import '../network/api_client.dart';
import '../network/auth_interceptor.dart';
import '../session/device_registration_service.dart';
import '../storage/token_storage.dart';
import '../utils/file_picker_service.dart';

/// Shared service locator instance used across every Nubia app and package.
final GetIt getIt = GetIt.instance;

/// Registers the cross-app infrastructure: secure storage, token storage,
/// the auth interceptor and the configured [ApiClient].
///
/// Apps call this first in their bootstrap, then register their data layer
/// ([nubia_data.registerData]) and their own blocs.
void registerCore(GetIt gi) {
  if (!gi.isRegistered<KvStore>()) {
    gi.registerLazySingleton<KvStore>(createKvStore);
  }
  gi
    ..registerLazySingleton<TokenStorage>(() => TokenStorage(gi()))
    ..registerLazySingleton<AuthInterceptor>(() => AuthInterceptor(gi()))
    ..registerLazySingleton<ApiClient>(() => ApiClient(gi()))
    ..registerLazySingleton<FilePickerService>(
      () => const DefaultFilePickerService(),
    )
    ..registerLazySingleton<DeviceRegistrationService>(
      () => DeviceRegistrationService(gi()),
    );
}
