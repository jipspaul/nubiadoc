import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/agenda/agenda_bloc.dart';
import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/dashboard/dashboard_bloc.dart';
import '../features/consultation_clinique/consultation_clinique_bloc.dart';
import '../features/ordonnances/ordonnances_bloc.dart';
import '../features/patients/patients_bloc.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
import 'pro_auth_cubit.dart';

void registerPro(GetIt gi) {
  gi.registerFactory<ProAuthCubit>(
    () => ProAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
      app: 'practicien',
    ),
  );

  gi.registerFactory<DashboardBloc>(
    () => DashboardBloc(getSummary: gi<GetProDashboardSummaryUseCase>()),
  );

  gi.registerFactory<WaitingRoomBloc>(
    () => WaitingRoomBloc(
      listWaitingRoom: gi<ListWaitingRoomUseCase>(),
      callNext: gi<CallNextUseCase>(),
    ),
  );

  gi.registerFactory<AgendaBloc>(
    () => AgendaBloc(
      getAgenda: gi<GetCabinetAgendaUseCase>(),
      confirmAppointment: gi<ConfirmAppointmentUseCase>(),
      startConsultation: gi<StartConsultationUseCase>(),
    ),
  );

  gi.registerFactory<CabinetMessagingBloc>(
    () => CabinetMessagingBloc(
      listConversations: gi<ListCabinetConversationsUseCase>(),
      getMessages: gi<GetCabinetConversationUseCase>(),
      sendMessage: gi<SendMessageCabinetUseCase>(),
    ),
  );

  gi.registerFactory<ConsultationCliniqueBloc>(
    () => ConsultationCliniqueBloc(
      getSession: gi<GetSessionUseCase>(),
      addAct: gi<AddActUseCase>(),
      completeSession: gi<CompleteSessionUseCase>(),
    ),
  );

  gi.registerFactory<OrdonnancesBloc>(
    () => OrdonnancesBloc(
      create: gi<CreatePrescriptionUseCase>(),
      sign: gi<SignPrescriptionUseCase>(),
    ),
  );

  gi.registerFactory<PatientsBloc>(
    () => PatientsBloc(
      listPatients: gi<ListCabinetPatientsUseCase>(),
      getPatient: gi<GetCabinetPatientUseCase>(),
      updateNotes: gi<UpdatePatientNotesUseCase>(),
    ),
  );
}
