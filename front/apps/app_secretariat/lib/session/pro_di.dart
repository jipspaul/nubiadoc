import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_auth_cubit.dart';
import '../features/agenda/agenda_bloc.dart';
import '../features/admin_membres/admin_membres_bloc.dart';
import '../features/admin_membres/members_access_cubit.dart';
import '../features/admin_secretariats/admin_secretariats_bloc.dart';
import '../features/appointment_motifs/appointment_motifs_bloc.dart';
import '../features/appointments/appointments_bloc.dart';
import '../features/audit_log/audit_log_access_cubit.dart';
import '../features/audit_log/audit_log_bloc.dart';
import '../features/bookable_slots/bookable_slots_bloc.dart';
import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/cabinet_payouts/cabinet_payouts_bloc.dart';
import '../features/cabinet_stats/cabinet_stats_bloc.dart';
import '../features/devis/devis_bloc.dart';
import '../features/patients/patients_bloc.dart';
import '../features/stock/stock_bloc.dart';
import '../features/waiting_list/waiting_list_bloc.dart';
import '../features/waiting_room/waiting_room_bloc.dart';

void registerPro(GetIt gi) {
  gi
    ..registerFactory<ProAuthCubit>(
      () => ProAuthCubit(
        login: gi<LoginUseCase>(),
        logout: gi<LogoutUseCase>(),
        register: gi<RegisterUseCase>(),
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
    ..registerFactory<AgendaBloc>(
      () => AgendaBloc(
        getAgenda: gi<GetCabinetAgendaUseCase>(),
        createAppointment: gi<CreateCabinetAppointmentUseCase>(),
        confirmAppointment: gi<ConfirmAppointmentUseCase>(),
        rescheduleAppointment: gi<RescheduleAppointmentUseCase>(),
        listSlots: gi<ListBookableSlotsUseCase>(),
      ),
    )
    ..registerFactory<PatientsBloc>(
      () => PatientsBloc(
        listPatients: gi<ListCabinetPatientsUseCase>(),
        createPatient: gi<CreateCabinetPatientUseCase>(),
      ),
    )
    ..registerFactory<WaitingListBloc>(
      () => WaitingListBloc(
        listWaitingList: gi<ListWaitingListUseCase>(),
        offerSlot: gi<OfferSlotToWaitingPatientUseCase>(),
      ),
    )
    ..registerFactory<DevisBloc>(
      () => DevisBloc(
        listQuotes: gi<ListCabinetQuotesUseCase>(),
        getQuote: gi<GetCabinetQuoteUseCase>(),
      ),
    )
    ..registerFactory<BookableSlotsBloc>(
      () => BookableSlotsBloc(
        listSlots: gi<ListBookableSlotsUseCase>(),
        createSlot: gi<CreateSlotUseCase>(),
        listPractitioners: gi<ListCabinetPractitionersUseCase>(),
      ),
    )
    ..registerFactory<AdminMembresBloc>(
      () => AdminMembresBloc(
        listMembers: gi<ListMembersUseCase>(),
        listSecretariats: gi<ListSecretiariatsUseCase>(),
        inviteMember: gi<InviteMemberUseCase>(),
      ),
    )
    ..registerFactory<MembersAccessCubit>(
      () => MembersAccessCubit(gi<ListMembersUseCase>()),
    )
    ..registerFactory<AppointmentMotifsBloc>(
      () => AppointmentMotifsBloc(
        list: gi<ListAppointmentMotifsUseCase>(),
        create: gi<CreateAppointmentMotifUseCase>(),
        update: gi<UpdateAppointmentMotifUseCase>(),
        delete: gi<DeleteAppointmentMotifUseCase>(),
      ),
    )
    ..registerFactory<AdminSecretiariatsBloc>(
      () => AdminSecretiariatsBloc(
        listSecretariats: gi<ListSecretiariatsUseCase>(),
        addSecretariat: gi<AddSecretariatUseCase>(),
      ),
    )
    ..registerFactory<AppointmentsBloc>(
      () => AppointmentsBloc(
        listAppointments: gi<ListCabinetAppointmentsUseCase>(),
        create: gi<CreateCabinetAppointmentUseCase>(),
        confirm: gi<ConfirmAppointmentUseCase>(),
        reschedule: gi<RescheduleAppointmentUseCase>(),
      ),
    )
    ..registerFactory<CabinetMessagingBloc>(
      () => CabinetMessagingBloc(
        listConversations: gi<ListCabinetConversationsUseCase>(),
        getMessages: gi<GetCabinetConversationUseCase>(),
        sendMessage: gi<SendMessageCabinetUseCase>(),
        convertToAppointment: gi<ConvertConversationToAppointmentUseCase>(),
      ),
    )
    ..registerFactory<StockBloc>(
      () => StockBloc(
        list: gi<ListStockRequestsUseCase>(),
        create: gi<CreateStockRequestUseCase>(),
      ),
    )
    ..registerFactory<CabinetStatsBloc>(
      () => CabinetStatsBloc(
        getActivityStats: gi<GetCabinetActivityStatsUseCase>(),
        getBillingStats: gi<GetCabinetBillingStatsUseCase>(),
      ),
    )
    ..registerFactory<CabinetPayoutsBloc>(
      () => CabinetPayoutsBloc(getPayouts: gi<GetCabinetPayoutsUseCase>()),
    )
    ..registerFactory<AuditLogBloc>(
      () => AuditLogBloc(getAuditLog: gi<GetAuditLogUseCase>()),
    )
    ..registerFactory<AuditLogAccessCubit>(
      () => AuditLogAccessCubit(gi<GetAuditLogUseCase>()),
    );
}
