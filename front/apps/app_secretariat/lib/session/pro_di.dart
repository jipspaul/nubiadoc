import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_auth_cubit.dart';
import '../features/admin_membres/admin_membres_bloc.dart';
import '../features/patients/patients_bloc.dart';
import '../features/waiting_room/waiting_room_bloc.dart';

void registerPro(GetIt gi) {
  gi
    ..registerFactory<ProAuthCubit>(
      () => ProAuthCubit(
        login: gi<LoginUseCase>(),
        logout: gi<LogoutUseCase>(),
        tokenStorage: gi<TokenStorage>(),
        deviceRegistration: gi<DeviceRegistrationService>(),
        app: 'secretariat',
      ),
    )
    ..registerFactory<WaitingRoomBloc>(
      () => WaitingRoomBloc(
        listWaitingRoom: gi<ListWaitingRoomUseCase>(),
        callNext: gi<CallNextUseCase>(),
      ),
    )
    ..registerFactory<PatientsBloc>(
      () => PatientsBloc(listPatients: gi<ListCabinetPatientsUseCase>()),
    )
    ..registerFactory<AdminMembresBloc>(
      () => AdminMembresBloc(
        listMembers: gi<ListMembersUseCase>(),
        listSecretariats: gi<ListSecretiariatsUseCase>(),
      ),
    );
}
