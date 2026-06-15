import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_auth_cubit.dart';

void registerPro(GetIt gi) {
  gi.registerFactory<ProAuthCubit>(
    () => ProAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
    ),
  );
}
