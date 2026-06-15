import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'auth_cubit.dart';

/// Registers patient-app blocs/cubits on top of registerCore + registerData.
void registerPatient(GetIt gi) {
  gi.registerFactory<AuthCubit>(
    () => AuthCubit(
      login: gi<LoginUseCase>(),
      getMe: gi<GetMeUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
    ),
  );
}
