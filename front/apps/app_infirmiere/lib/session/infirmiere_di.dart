import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/nurse/nurse_cubit.dart';
import 'infirmiere_auth_cubit.dart';

void registerInfirmiere(GetIt gi) {
  gi.registerLazySingleton<InfirmiereAuthCubit>(
    () => InfirmiereAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
    ),
  );

  gi.registerFactory<NurseCubit>(() => NurseCubit(gi<ApiClient>()));
}
