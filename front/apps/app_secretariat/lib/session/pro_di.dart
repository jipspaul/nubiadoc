import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_auth_cubit.dart';
import '../features/waiting_room/waiting_room_bloc.dart';

void registerPro(GetIt gi) {
  gi
    ..registerFactory<ProAuthCubit>(
      () => ProAuthCubit(
        login: gi<LoginUseCase>(),
        logout: gi<LogoutUseCase>(),
        tokenStorage: gi<TokenStorage>(),
      ),
    )
    ..registerFactory<WaitingRoomBloc>(
      () => WaitingRoomBloc(
        listWaitingRoom: gi<ListWaitingRoomUseCase>(),
        callNext: gi<CallNextUseCase>(),
      ),
    );
}
