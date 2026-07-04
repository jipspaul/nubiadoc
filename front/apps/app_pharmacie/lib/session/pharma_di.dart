import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharma_auth_cubit.dart';

/// Registers the pharmacie app blocs. Les blocs métier (commandes, scan,
/// stock, messagerie, devis) arrivent avec les lots F4–F6.
void registerPharma(GetIt gi) {
  gi.registerLazySingleton<PharmaAuthCubit>(
    () => PharmaAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
      app: 'pharmacie',
    ),
  );
}
