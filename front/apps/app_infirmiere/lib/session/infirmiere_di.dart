import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/notification_prefs/notification_prefs_cubit.dart';
import '../features/notifications/notifications_bloc.dart';
import '../features/nurse/nurse_cubit.dart';
import 'infirmiere_auth_cubit.dart';

void registerInfirmiere(GetIt gi) {
  gi.registerLazySingleton<InfirmiereAuthCubit>(
    () => InfirmiereAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
      api: gi<ApiClient>(),
    ),
  );

  // Le refresh réécrit un token de login kind:"pro" : on re-scope
  // immédiatement le contexte infirmier sinon /v1/nurse/* casse en 403
  // au bout des 900 s de vie du JWT nurse.
  gi<AuthInterceptor>().onTokensRefreshed = (plainDio) =>
      gi<InfirmiereAuthCubit>().reselectContext(plainDio);

  gi.registerFactory<NurseCubit>(() => NurseCubit(gi<ApiClient>()));

  gi.registerFactory<NotificationsBloc>(
    () => NotificationsBloc(repository: gi<NotificationRepository>()),
  );

  gi.registerFactory<NotificationPrefsCubit>(
    () => NotificationPrefsCubit(
      get: gi<GetProNotificationPreferencesUseCase>(),
      update: gi<UpdateProNotificationPreferencesUseCase>(),
    ),
  );
}
