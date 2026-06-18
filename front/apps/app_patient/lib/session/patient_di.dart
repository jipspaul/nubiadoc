import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/appointments/appointments_bloc.dart';
import '../features/mes_rdv/mes_rdv_bloc.dart';
import '../features/home/home_bloc.dart';
import '../features/profile/profile_bloc.dart';
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

  gi.registerFactory<AppointmentsBloc>(
    () => AppointmentsBloc(
      searchProviders: gi<SearchProvidersUseCase>(),
      searchSlots: gi<SearchSlotsUseCase>(),
      holdSlot: gi<HoldSlotUseCase>(),
      bookAppointment: gi<BookAppointmentUseCase>(),
    ),
  );

  gi.registerFactory<MesRdvBloc>(
    () => MesRdvBloc(
      getUpcoming: gi<GetUpcomingAppointmentsUseCase>(),
      getHistory: gi<GetAppointmentHistoryUseCase>(),
      cancel: gi<CancelAppointmentUseCase>(),
      checkin: gi<CheckinAppointmentUseCase>(),
    ),
  );

  gi.registerFactory<ProfileBloc>(
    () => ProfileBloc(getAccount: gi<GetAccountUseCase>()),
  );

  gi.registerFactory<HomeBloc>(
    () => HomeBloc(getDashboardSummary: gi<GetDashboardSummaryUseCase>()),
  );
}
