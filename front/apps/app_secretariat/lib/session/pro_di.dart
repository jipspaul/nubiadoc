import 'package:get_it/get_it.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_auth_cubit.dart';
import '../features/agenda/agenda_bloc.dart';
import '../features/admin_membres/admin_membres_bloc.dart';
import '../features/admin_membres/members_access_cubit.dart';
import '../features/admin_secretariats/admin_secretariats_bloc.dart';
import '../features/appointment_motifs/appointment_motifs_bloc.dart';
import '../features/appointments/appointments_bloc.dart';
import '../features/correspondents/correspondent_stats_cubit.dart';
import '../features/correspondents/correspondents_bloc.dart';
import '../features/audit_log/audit_log_access_cubit.dart';
import '../features/audit_log/audit_log_bloc.dart';
import '../features/bookable_slots/bookable_slots_bloc.dart';
import '../features/cabinet_brief/cabinet_brief_bloc.dart';
import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/cabinet_payouts/cabinet_payouts_bloc.dart';
import '../features/cabinet_stats/cabinet_stats_bloc.dart';
import '../features/dashboard/cash_collection_cubit.dart';
import '../features/dashboard/expiring_quotes_summary_cubit.dart';
import '../features/dashboard/patient_messages_summary_cubit.dart';
import '../features/dashboard/rail_badges_cubit.dart';
import '../features/dashboard/waiting_room_summary_cubit.dart';
import '../features/devis/devis_bloc.dart';
import '../features/devis/invoice_reminder_cubit.dart';
import '../features/notification_prefs/notification_prefs_cubit.dart';
import '../features/patients/patients_bloc.dart';
import '../features/stock/stock_bloc.dart';
import '../features/stock/stock_inventory_bloc.dart';
import '../features/stock/stock_locations_bloc.dart';
import '../features/tasks/tasks_bloc.dart';
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
        api: gi<ApiClient>(),
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
        checkinAppointment: gi<CabinetCheckinAppointmentUseCase>(),
        cancelAppointment: gi<CancelCabinetAppointmentUseCase>(),
        rescheduleAppointment: gi<RescheduleAppointmentUseCase>(),
        listSlots: gi<ListBookableSlotsUseCase>(),
        listPractitioners: gi<ListCabinetPractitionersUseCase>(),
        createAppointmentTask: gi<CreateAppointmentTaskUseCase>(),
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
        sendQuote: gi<SendCabinetQuoteUseCase>(),
      ),
    )
    ..registerFactory<InvoiceReminderCubit>(
      () => InvoiceReminderCubit(
        listReminders: gi<ListInvoiceRemindersUseCase>(),
        sendReminder: gi<SendInvoiceReminderUseCase>(),
      ),
    )
    ..registerFactory<RailBadgesCubit>(
      () => RailBadgesCubit(
        listWaitingRoom: gi<ListWaitingRoomUseCase>(),
        listWaitingList: gi<ListWaitingListUseCase>(),
        listQuotes: gi<ListCabinetQuotesUseCase>(),
        listConversations: gi<ListCabinetConversationsUseCase>(),
      ),
    )
    ..registerFactory<CashCollectionCubit>(
      () => CashCollectionCubit(
        getSummary: gi<GetCashCollectionSummaryUseCase>(),
      ),
    )
    ..registerFactory<WaitingRoomSummaryCubit>(
      () => WaitingRoomSummaryCubit(
        listWaitingRoom: gi<ListWaitingRoomUseCase>(),
      ),
    )
    ..registerFactory<PatientMessagesSummaryCubit>(
      () => PatientMessagesSummaryCubit(
        listConversations: gi<ListCabinetConversationsUseCase>(),
      ),
    )
    ..registerFactory<ExpiringQuotesSummaryCubit>(
      () => ExpiringQuotesSummaryCubit(
        listQuotes: gi<ListCabinetQuotesUseCase>(),
      ),
    )
    ..registerFactory<OpportunitiesCubit>(
      () => OpportunitiesCubit(
        getOpportunities: gi<GetCabinetOpportunitiesUseCase>(),
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
        listSecretariats: gi<ListSecretariatsUseCase>(),
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
    ..registerFactory<CorrespondentsBloc>(
      () => CorrespondentsBloc(
        list: gi<ListCabinetCorrespondentsUseCase>(),
        create: gi<CreateCabinetCorrespondentUseCase>(),
        update: gi<UpdateCabinetCorrespondentUseCase>(),
        delete: gi<DeleteCabinetCorrespondentUseCase>(),
      ),
    )
    ..registerFactory<CorrespondentStatsCubit>(
      () =>
          CorrespondentStatsCubit(getStats: gi<GetCorrespondentStatsUseCase>()),
    )
    ..registerFactory<AdminSecretariatsBloc>(
      () => AdminSecretariatsBloc(
        listSecretariats: gi<ListSecretariatsUseCase>(),
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
        resend: gi<ResendStockRequestUseCase>(),
      ),
    )
    ..registerFactory<StockInventoryBloc>(
      () => StockInventoryBloc(
        list: gi<ListStockItemsUseCase>(),
        addMovement: gi<AddStockMovementUseCase>(),
      ),
    )
    ..registerFactory<StockLocationsBloc>(
      () => StockLocationsBloc(
        listLocations: gi<ListStockLocationsUseCase>(),
        listItems: gi<ListStockItemsUseCase>(),
        listItemLocations: gi<ListItemLocationsUseCase>(),
        createLocation: gi<CreateStockLocationUseCase>(),
        transfer: gi<TransferStockUseCase>(),
        setThreshold: gi<SetItemLocationThresholdUseCase>(),
      ),
    )
    ..registerFactory<CabinetStatsBloc>(
      () => CabinetStatsBloc(
        getActivityStats: gi<GetCabinetActivityStatsUseCase>(),
        getBillingStats: gi<GetCabinetBillingStatsUseCase>(),
      ),
    )
    ..registerFactory<CabinetBriefBloc>(
      () => CabinetBriefBloc(
        getBrief: gi<GetCabinetBriefUseCase>(),
        getBriefPdf: gi<GetCabinetBriefPdfUseCase>(),
      ),
    )
    ..registerFactory<CabinetPayoutsBloc>(
      () => CabinetPayoutsBloc(
        getPayouts: gi<GetCabinetPayoutsUseCase>(),
        markReconciled: gi<MarkPayoutReconciledUseCase>(),
        flagToAccountant: gi<FlagPayoutToAccountantUseCase>(),
      ),
    )
    ..registerFactory<AuditLogBloc>(
      () => AuditLogBloc(getAuditLog: gi<GetAuditLogUseCase>()),
    )
    ..registerFactory<AuditLogAccessCubit>(
      () => AuditLogAccessCubit(gi<GetAuditLogUseCase>()),
    )
    ..registerFactory<NotificationPrefsCubit>(
      () => NotificationPrefsCubit(
        get: gi<GetProNotificationPreferencesUseCase>(),
        update: gi<UpdateProNotificationPreferencesUseCase>(),
      ),
    )
    ..registerFactory<TasksBloc>(
      () => TasksBloc(
        listTasks: gi<ListCabinetTasksUseCase>(),
        createTask: gi<CreateCabinetTaskUseCase>(),
        completeTask: gi<CompleteCabinetTaskUseCase>(),
      ),
    );
}
