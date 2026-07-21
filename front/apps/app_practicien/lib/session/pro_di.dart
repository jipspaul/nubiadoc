import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_data/nubia_data.dart';

import '../features/agenda/agenda_bloc.dart';
import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/dashboard/dashboard_bloc.dart';
import '../features/dashboard/today_notes_bloc.dart';
import '../features/consultation_clinique/consultation_clinique_bloc.dart';
import '../features/devis/devis_bloc.dart';
import '../features/ordonnances/ordonnances_bloc.dart';
import '../features/ordonnances/send_to_pharmacy_cubit.dart';
import '../features/patients/patients_bloc.dart';
import '../features/cabinet/cabinet_info_cubit.dart';
import '../features/register/pro_register_cubit.dart';
import '../features/consultation_clinique/ccam_picker.dart';
import '../features/consultation_clinique/api_get_acts_use_case.dart';
import '../features/stock/stock_bloc.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
import 'pro_auth_cubit.dart';

void registerPro(GetIt gi) {
  gi.registerLazySingleton<ProAuthCubit>(
    () => ProAuthCubit(
      login: gi<LoginUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
      app: 'practicien',
    ),
  );

  gi.registerFactory<ProRegisterUseCase>(
    () => ProRegisterUseCase(gi<AuthRepository>()),
  );

  gi.registerFactory<ProRegisterCubit>(
    () => ProRegisterCubit(
      register: gi<ProRegisterUseCase>(),
      authCubit: gi<ProAuthCubit>(),
    ),
  );

  gi.registerFactory<CabinetInfoCubit>(
    () => CabinetInfoCubit(updateCabinet: gi<UpdateCabinetUseCase>()),
  );

  gi.registerFactory<DashboardBloc>(
    () => DashboardBloc(getSummary: gi<GetProDashboardSummaryUseCase>()),
  );

  gi.registerFactory<TodayNotesBloc>(
    () => TodayNotesBloc(getTodayNotes: gi<GetTodayNotesUseCase>()),
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
      convertToAppointment: gi<ConvertConversationToAppointmentUseCase>(),
    ),
  );

  gi.registerFactory<GetActsUseCase>(
    () => ApiGetActsUseCase(gi<ClinicalSessionApi>()),
  );

  gi.registerFactory<ConsultationCliniqueBloc>(
    () => ConsultationCliniqueBloc(
      getSession: gi<GetSessionUseCase>(),
      addAct: gi<AddActUseCase>(),
      completeSession: gi<CompleteSessionUseCase>(),
      listSessions: gi<ListClinicalSessionsUseCase>(),
      saveNote: gi<SaveNoteUseCase>(),
    ),
  );

  gi.registerFactory<SendToPharmacyCubit>(
    () => SendToPharmacyCubit(
      getPatientPharmacy: gi<GetPatientPharmacyUseCase>(),
      sendToPharmacy: gi<SendPrescriptionToPharmacyUseCase>(),
    ),
  );

  gi.registerFactory<OrdonnancesBloc>(
    () => OrdonnancesBloc(
      create: gi<CreatePrescriptionUseCase>(),
      sign: gi<SignPrescriptionUseCase>(),
      listTemplates: gi<ListPrescriptionTemplatesUseCase>(),
      applyTemplate: gi<ApplyPrescriptionTemplateUseCase>(),
    ),
  );

  gi.registerFactory<DevisBloc>(
    () => DevisBloc(
      list: gi<ListCabinetQuotesUseCase>(),
      getById: gi<GetCabinetQuoteUseCase>(),
      send: gi<SendCabinetQuoteUseCase>(),
    ),
  );

  gi.registerFactory<PatientsBloc>(
    () => PatientsBloc(
      listPatients: gi<ListCabinetPatientsUseCase>(),
      getPatient: gi<GetCabinetPatientUseCase>(),
      updateNotes: gi<UpdatePatientNotesUseCase>(),
      listAppointments: gi<ListCabinetAppointmentsUseCase>(),
    ),
  );

  gi.registerFactory<StockBloc>(
    () => StockBloc(
      list: gi<ListStockRequestsUseCase>(),
      create: gi<CreateStockRequestUseCase>(),
    ),
  );
}
