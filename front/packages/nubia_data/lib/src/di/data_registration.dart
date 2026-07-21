import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../cache/appointments_cache.dart';
import '../cache/drift/drift_appointments_cache.dart';
import '../cache/drift/nubia_database.dart';
import '../remote/account/account_api.dart';
import '../remote/auth/auth_api.dart';
import '../remote/billing/billing_api.dart';
import '../remote/cabinet_info/cabinet_info_api.dart';
import '../remote/cabinet_agenda/cabinet_agenda_api.dart';
import '../remote/cabinet_appointments/cabinet_appointments_api.dart';
import '../remote/cabinet_dashboard/cabinet_dashboard_api.dart';
import '../remote/cabinet_messaging/cabinet_messaging_api.dart';
import '../remote/cabinet_patients/cabinet_patients_api.dart';
import '../remote/patient_tags/patient_tags_api.dart';
import '../remote/patient_documents/patient_documents_api.dart';
import '../remote/dental_chart/dental_chart_api.dart';
import '../remote/treatment_plans/treatment_plans_api.dart';
import '../remote/cabinet_quotes/cabinet_quotes_api.dart';
import '../remote/clinical/clinical_session_api.dart';
import '../remote/consultation/consultation_api.dart';
import '../remote/dashboard/dashboard_api.dart';
import '../remote/documents/document_api.dart';
import '../remote/members/members_api.dart';
import '../remote/messaging/messaging_api.dart';
import '../remote/notifications/notification_api.dart';
import '../remote/patient_pharmacy/patient_pharmacy_api.dart';
import '../remote/pharmacy_directory/pharmacy_directory_api.dart';
import '../remote/pharmacy_orders/pharmacy_orders_api.dart';
import '../remote/pharmacy_quotes/pharmacy_quotes_api.dart';
import '../remote/pharmacy_session/pharmacy_session_api.dart';
import '../remote/pharmacy_stock/pharmacy_stock_api.dart';
import '../remote/prescriptions/prescription_api.dart';
import '../remote/reviews/review_api.dart';
import '../remote/scheduling/scheduling_api.dart';
import '../remote/search/search_api.dart';
import '../remote/secretariat/secretariat_api.dart';
import '../remote/slots/slots_api.dart';
import '../remote/today_notes/today_notes_api.dart';
import '../remote/waiting_room/waiting_room_api.dart';
import '../repositories/account_repository_impl.dart';
import '../repositories/search_repository_impl.dart';
import '../repositories/appointment_repository_impl.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/billing_repository_impl.dart';
import '../repositories/cabinet_repository_impl.dart';
import '../repositories/cabinet_agenda_repository_impl.dart';
import '../repositories/cabinet_appointments_repository_impl.dart';
import '../repositories/cabinet_dashboard_repository_impl.dart';
import '../repositories/cabinet_message_repository_impl.dart';
import '../repositories/cabinet_patients_repository_impl.dart';
import '../repositories/patient_tags_repository_impl.dart';
import '../repositories/patient_documents_repository_impl.dart';
import '../repositories/dental_chart_repository_impl.dart';
import '../repositories/treatment_plans_repository_impl.dart';
import '../repositories/cabinet_quotes_repository_impl.dart';
import '../repositories/cached_appointments_repository_impl.dart';
import '../repositories/clinical_session_repository_impl.dart';
import '../repositories/consultation_repository_impl.dart';
import '../repositories/dashboard_repository_impl.dart';
import '../repositories/document_repository_impl.dart';
import '../repositories/members_repository_impl.dart';
import '../repositories/message_repository_impl.dart';
import '../repositories/notification_repository_impl.dart';
import '../repositories/patient_pharmacy_repository_impl.dart';
import '../repositories/pharmacy_directory_repository_impl.dart';
import '../repositories/pharmacy_orders_repository_impl.dart';
import '../repositories/pharmacy_quotes_repository_impl.dart';
import '../repositories/pharmacy_session_repository_impl.dart';
import '../repositories/prescription_repository_impl.dart';
import '../repositories/review_repository_impl.dart';
import '../repositories/secretariat_repository_impl.dart';
import '../repositories/slots_repository_impl.dart';
import '../repositories/today_notes_repository_impl.dart';
import '../repositories/stock_requests_repository_impl.dart';
import '../repositories/user_settings_repository_impl.dart';
import '../repositories/waiting_room_repository_impl.dart';
import '../realtime/polling_pharmacy_order_events.dart';
import '../realtime/ws_client.dart';
import '../realtime/ws_pharmacy_order_events.dart';

/// Registers the data layer: Dio APIs, repository implementations and use cases.
///
/// Call after `registerCore(gi)` so that [ApiClient]/[TokenStorage] are
/// available. GetIt resolves each constructor argument by type via `gi()`.
///
/// [includeClinical] gates the clinical + prescription stacks. The secretariat
/// app passes `false`, guaranteeing no clinical repository/use case is ever
/// registered in its container (no code path to clinical data).
///
/// [includePro] gates the pro/cabinet data stack (9 APIs + repos for the
/// practitioner and secretariat surfaces). Pass `true` in the pro apps.
/// When `includePro == true` and `includeClinical == false`, the
/// [ConsultationApi]/[ConsultationRepository] are NOT registered (secretariat
/// binary does not access clinical data).
///
/// [useCache] enables the offline cache layer for appointments. When `true`,
/// [AppointmentRepository] is backed by [CachedAppointmentsRepositoryImpl]
/// wrapping the remote implementation via a Drift SQLite cache.
///
/// [includePharmacy] gates the pharmacy-tenant stack (app pharmacie : JWT
/// `kind:"pharma"`, /v1/pharmacy/*). Mutually exclusive with [includePro].
/// When `false`, the patient-side pharmacy stack (/v1/account/*) is
/// registered instead — the pharmacy-tenant repositories are never present
/// in the other apps' containers.
void registerData(
  GetIt gi, {
  bool includeClinical = true,
  bool includePro = false,
  bool includePharmacy = false,
  bool useCache = false,
}) {
  assert(
    !(includePro && includePharmacy),
    'includePro et includePharmacy sont mutuellement exclusifs',
  );
  // --- APIs (each takes ApiClient) -----------------------------------------
  gi
    ..registerLazySingleton<AccountApi>(() => AccountApi(gi()))
    ..registerLazySingleton<AuthApi>(() => AuthApi(gi()))
    ..registerLazySingleton<BillingApi>(() => BillingApi(gi()))
    ..registerLazySingleton<DashboardApi>(() => DashboardApi(gi()))
    ..registerLazySingleton<DocumentApi>(() => DocumentApi(gi()))
    ..registerLazySingleton<MessagingApi>(() => MessagingApi(gi()))
    ..registerLazySingleton<NotificationApi>(() => NotificationApi(gi()))
    ..registerLazySingleton<ReviewApi>(() => ReviewApi(gi()))
    ..registerLazySingleton<SchedulingApi>(() => SchedulingApi(gi()))
    ..registerLazySingleton<SearchApi>(() => SearchApi(gi()));

  // --- Repositories ---------------------------------------------------------
  if (useCache) {
    gi
      ..registerLazySingleton<NubiaDatabase>(NubiaDatabase.production)
      ..registerLazySingleton<AppointmentsCache>(
        () => DriftAppointmentsCache(gi()),
      );
  }

  gi
    ..registerLazySingleton<UserSettingsRepository>(
      () => InMemoryUserSettingsRepository(),
    )
    ..registerLazySingleton<AccountRepository>(
      () => AccountRepositoryImpl(gi()),
    )
    ..registerLazySingleton<AppointmentRepository>(
      () => useCache
          ? CachedAppointmentsRepositoryImpl(
              remote: AppointmentRepositoryImpl(gi()),
              cache: gi(),
            )
          : AppointmentRepositoryImpl(gi()),
    )
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(gi(), gi(), gi()),
    )
    ..registerLazySingleton<BillingRepository>(
      () => BillingRepositoryImpl(gi()),
    )
    ..registerLazySingleton<DashboardRepository>(
      () => DashboardRepositoryImpl(gi()),
    )
    ..registerLazySingleton<DocumentRepository>(
      () => DocumentRepositoryImpl(gi()),
    )
    ..registerLazySingleton<MessageRepository>(
      () => MessageRepositoryImpl(gi(), gi()),
    )
    ..registerLazySingleton<NotificationRepository>(
      () => NotificationRepositoryImpl(gi()),
    )
    ..registerLazySingleton<ReviewRepository>(
      () => ReviewRepositoryImpl(gi()),
    )
    ..registerLazySingleton<SearchRepository>(
      () => SearchRepositoryImpl(gi()),
    );

  // --- Annuaire pharmacie (toutes les apps) ---------------------------------
  gi
    ..registerLazySingleton<PharmacyDirectoryApi>(
      () => PharmacyDirectoryApi(gi()),
    )
    ..registerLazySingleton<PharmacyDirectoryRepository>(
      () => PharmacyDirectoryRepositoryImpl(gi()),
    )
    ..registerFactory(() => SearchPharmaciesUseCase(gi()))
    ..registerFactory(() => GetPatientPharmacyUseCase(gi()));

  // --- Use cases ------------------------------------------------------------
  _registerUseCases(gi);

  if (includeClinical) {
    _registerClinical(gi);
  }

  if (includePro) {
    _registerPro(gi, includeClinical: includeClinical);
  }

  if (includePharmacy) {
    _registerPharmacy(gi);
  } else {
    _registerPatientPharmacy(gi);
  }
}

/// Espace patient : pharmacie déclarée, commandes click-and-collect,
/// devis d'officine (/v1/account/*).
void _registerPatientPharmacy(GetIt gi) {
  gi
    ..registerLazySingleton<PatientPharmacyApi>(
      () => PatientPharmacyApi(gi()),
    )
    ..registerLazySingleton<PatientPharmacyRepository>(
      () => PatientPharmacyRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PharmacyQuotesApi>(
      () => PharmacyQuotesApi(gi(), space: PharmacyQuotesSpace.patient),
    )
    ..registerLazySingleton<PharmacyQuotesRepository>(
      () => PharmacyQuotesRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PharmacyOrderEventsPort>(
      // WebSocket (lot F10) avec fallback polling — swap invisible pour
      // les blocs (même port).
      () => WsPharmacyOrderEvents(
        client: WsClient(
          baseWsUrl: _wsUrl(),
          accessTokenProvider: () => gi<TokenStorage>().getAccessToken(),
        ),
        accessTokenProvider: () => gi<TokenStorage>().getAccessToken(),
        fallback: PollingPharmacyOrderEvents(
          fetchOrder: (id) => gi<PatientPharmacyRepository>().getOrder(id),
        ),
        fetchOrder: (id) => gi<PatientPharmacyRepository>().getOrder(id),
      ),
      dispose: (port) => port.dispose(),
    )
    ..registerFactory(() => GetMyPharmacyUseCase(gi()))
    ..registerFactory(() => SetMyPharmacyUseCase(gi()))
    ..registerFactory(() => CreatePharmacyOrderUseCase(gi()))
    ..registerFactory(() => ListMyPrescriptionsUseCase(gi()))
    ..registerFactory(() => ListPatientPharmacyOrdersUseCase(gi()))
    ..registerFactory(() => GetPatientPharmacyOrderUseCase(gi()))
    ..registerFactory(() => CancelPharmacyOrderUseCase(gi()))
    ..registerFactory(() => GetPickupTokenUseCase(gi()))
    ..registerFactory(() => WatchPatientPharmacyOrderUseCase(gi()))
    ..registerFactory(() => ListPharmacyQuotesUseCase(gi()))
    ..registerFactory(() => DecidePharmacyQuoteUseCase(gi()));
}

/// Espace pharmacie (tenant dédié, JWT kind="pharma") : commandes, stock,
/// devis, messagerie (mêmes formes JSON que /v1/cabinet/* via basePath).
void _registerPharmacy(GetIt gi) {
  gi
    ..registerLazySingleton<PharmacySessionApi>(
      () => PharmacySessionApi(gi()),
    )
    ..registerLazySingleton<PharmacySessionRepositoryImpl>(
      () => PharmacySessionRepositoryImpl(gi(), gi()),
    )
    ..registerLazySingleton<PharmacySessionRepository>(
      () => gi<PharmacySessionRepositoryImpl>(),
    )
    ..registerFactory(() => GetPharmacyMembershipsUseCase(gi()))
    ..registerFactory(() => SelectPharmacyContextUseCase(gi()))
    ..registerLazySingleton<PharmacyOrdersApi>(
      () => PharmacyOrdersApi(gi()),
    )
    ..registerLazySingleton<PharmacyOrdersRepository>(
      () => PharmacyOrdersRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PharmacyStockApi>(
      () => PharmacyStockApi(gi()),
    )
    ..registerLazySingleton<StockRequestsRepository>(
      () => StockRequestsRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PharmacyQuotesApi>(
      () => PharmacyQuotesApi(gi()),
    )
    ..registerLazySingleton<PharmacyQuotesRepository>(
      () => PharmacyQuotesRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetMessagingApi>(
      () => CabinetMessagingApi(gi(), basePath: '/pharmacy'),
    )
    ..registerLazySingleton<CabinetMessageRepository>(
      () => CabinetMessageRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PharmacyOrderEventsPort>(
      // WebSocket (lot F10) avec fallback polling — swap invisible pour
      // les blocs (même port).
      () => WsPharmacyOrderEvents(
        client: WsClient(
          baseWsUrl: _wsUrl(),
          accessTokenProvider: () => gi<TokenStorage>().getAccessToken(),
        ),
        accessTokenProvider: () => gi<TokenStorage>().getAccessToken(),
        fallback: PollingPharmacyOrderEvents(
          fetchOrders: () => gi<PharmacyOrdersRepository>().list(),
        ),
        fetchOrders: () => gi<PharmacyOrdersRepository>().list(),
      ),
      dispose: (port) => port.dispose(),
    )
    ..registerFactory(() => ListPharmacyOrdersUseCase(gi()))
    ..registerFactory(() => GetPharmacyOrderUseCase(gi()))
    ..registerFactory(() => AcceptPharmacyOrderUseCase(gi()))
    ..registerFactory(() => MarkPharmacyOrderReadyUseCase(gi()))
    ..registerFactory(() => RejectPharmacyOrderUseCase(gi()))
    ..registerFactory(() => ConfirmPharmacyPickupUseCase(gi()))
    ..registerFactory(() => GetPharmacyOrderPrescriptionUrlUseCase(gi()))
    ..registerFactory(() => WatchPharmacyOrdersUseCase(gi()))
    ..registerFactory(() => ListStockRequestsUseCase(gi()))
    ..registerFactory(() => RespondStockRequestUseCase(gi()))
    ..registerFactory(() => ListPharmacyQuotesUseCase(gi()))
    ..registerFactory(() => CreatePharmacyQuoteUseCase(gi()))
    ..registerFactory(() => SendPharmacyQuoteUseCase(gi()))
    ..registerFactory(() => ListCabinetConversationsUseCase(gi()))
    ..registerFactory(() => GetCabinetConversationUseCase(gi()))
    ..registerFactory(() => SendMessageCabinetUseCase(gi()));

  // Le refresh réécrit un token de login kind:"pro" : on re-scope
  // immédiatement le contexte pharmacie sinon /v1/pharmacy/* casse en 403
  // au bout des 900 s de vie du JWT pharma.
  gi<AuthInterceptor>().onTokensRefreshed = (plainDio) =>
      gi<PharmacySessionRepositoryImpl>().reselectContext(plainDio);
}

/// URL du WebSocket dérivée de l'API base (http→ws, /v1 → /v1/ws).
String _wsUrl() {
  final base = ApiConstants.baseUrl.replaceFirst('http', 'ws');
  return base.endsWith('/') ? '${base}ws' : '$base/ws';
}

void _registerUseCases(GetIt gi) {
  gi
    // auth
    ..registerFactory(() => LoginUseCase(gi()))
    ..registerFactory(() => LogoutUseCase(gi()))
    ..registerFactory(() => RegisterUseCase(gi()))
    ..registerFactory(() => GetMeUseCase(gi()))
    ..registerFactory(() => ForgotPasswordUseCase(gi()))
    ..registerFactory(() => ResetPasswordUseCase(gi()))
    // account
    ..registerFactory(() => GetAccountUseCase(gi()))
    ..registerFactory(() => AddDependentUseCase(gi()))
    ..registerFactory(() => DeleteDependentUseCase(gi()))
    ..registerFactory(() => SetConsentUseCase(gi()))
    ..registerFactory(() => GetAvatarUseCase(gi()))
    ..registerFactory(() => UpdateAvatarUseCase(gi()))
    ..registerFactory(() => UpdateNotificationPreferencesUseCase(gi()))
    ..registerFactory(() => UpdateAccountUseCase(gi()))
    ..registerFactory(() => GetCoverageUseCase(gi()))
    ..registerFactory(() => UpdateCoverageUseCase(gi()))
    ..registerFactory(() => GetNotificationPreferencesUseCase(gi()))
    ..registerFactory(() => ListConsentsUseCase(gi()))
    ..registerFactory(() => ListDependentsUseCase(gi()))
    ..registerFactory(() => UploadCoverageCardUseCase(gi()))
    ..registerFactory(() => GetReferringDoctorUseCase(gi()))
    ..registerFactory(() => SetReferringDoctorUseCase(gi()))
    // appointments
    ..registerFactory(() => BookAppointmentUseCase(gi()))
    ..registerFactory(() => CancelAppointmentUseCase(gi()))
    ..registerFactory(() => CheckinAppointmentUseCase(gi()))
    ..registerFactory(() => GetAppointmentByIdUseCase(gi()))
    ..registerFactory(() => GetAppointmentHistoryUseCase(gi()))
    ..registerFactory(() => GetUpcomingAppointmentsUseCase(gi()))
    ..registerFactory(() => ModifyAppointmentUseCase(gi()))
    ..registerFactory(() => GetDirectionsUseCase(gi()))
    ..registerFactory(() => GetAppointmentPreparationUseCase(gi()))
    // billing
    ..registerFactory(() => GetPendingQuotesUseCase(gi()))
    ..registerFactory(() => GetQuoteByIdUseCase(gi()))
    ..registerFactory(() => InitiateDepositUseCase(gi()))
    ..registerFactory(() => InitiateSignatureUseCase(gi()))
    // dashboard
    ..registerFactory(() => GetDashboardSummaryUseCase(gi()))
    // documents
    ..registerFactory(() => GetDocumentSignedUrlUseCase(gi()))
    ..registerFactory(() => GetDocumentsUseCase(gi()))
    ..registerFactory(() => UploadDocumentUseCase(gi()))
    // messaging
    ..registerFactory(() => GetConversationMessagesUseCase(gi()))
    ..registerFactory(() => GetConversationsUseCase(gi()))
    ..registerFactory(() => MarkConversationReadUseCase(gi()))
    ..registerFactory(() => SendMessageUseCase(gi()))
    // reviews
    ..registerFactory(() => GetProviderReviewsUseCase(gi()))
    ..registerFactory(() => SubmitReviewUseCase(gi()))
    // search
    ..registerFactory(() => ParseSearchUseCase(gi()))
    ..registerFactory(() => SearchProvidersUseCase(gi()))
    ..registerFactory(() => SearchSlotsUseCase(gi()))
    ..registerFactory(() => HoldSlotUseCase(gi()))
    ..registerFactory(() => ConfirmBookingUseCase(gi()))
    // notifications / devices
    ..registerFactory(() => RegisterDeviceUseCase(gi()));
}

void _registerClinical(GetIt gi) {
  gi
    ..registerLazySingleton<ClinicalSessionApi>(() => ClinicalSessionApi(gi()))
    ..registerLazySingleton<PrescriptionApi>(() => PrescriptionApi(gi()))
    ..registerLazySingleton<ClinicalSessionRepository>(
      () => ClinicalSessionRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PrescriptionRepository>(
      () => PrescriptionRepositoryImpl(gi()),
    )
    // clinical use cases
    ..registerFactory(() => AddActUseCase(gi()))
    ..registerFactory(() => CompleteSessionUseCase(gi()))
    ..registerFactory(() => GetSessionUseCase(gi()))
    ..registerFactory(() => ListClinicalSessionsUseCase(gi()))
    ..registerFactory(() => RemoveActUseCase(gi()))
    ..registerFactory(() => SaveNoteUseCase(gi()))
    ..registerFactory(() => StartSessionUseCase(gi()))
    // prescription use cases
    ..registerFactory(() => CreatePrescriptionUseCase(gi()))
    ..registerFactory(() => SignPrescriptionUseCase(gi()))
    ..registerFactory(() => SendPrescriptionToPharmacyUseCase(gi()));
}

/// Registers the pro/cabinet data stack.
///
/// [includeClinical] controls whether [ConsultationApi] and
/// [ConsultationRepository] are registered — secretariat apps pass `false`.
void _registerPro(GetIt gi, {bool includeClinical = true}) {
  gi
    // APIs
    ..registerLazySingleton<CabinetInfoApi>(
      () => CabinetInfoApi(gi()),
    )
    ..registerLazySingleton<CabinetDashboardApi>(
      () => CabinetDashboardApi(gi()),
    )
    ..registerLazySingleton<CabinetPatientsApi>(
      () => CabinetPatientsApi(gi()),
    )
    ..registerLazySingleton<PatientTagsApi>(
      () => PatientTagsApi(gi()),
    )
    ..registerLazySingleton<PatientDocumentsApi>(
      () => PatientDocumentsApi(gi()),
    )
    ..registerLazySingleton<DentalChartApi>(
      () => DentalChartApi(gi()),
    )
    ..registerLazySingleton<TreatmentPlansApi>(
      () => TreatmentPlansApi(gi()),
    )
    ..registerLazySingleton<CabinetAgendaApi>(
      () => CabinetAgendaApi(gi()),
    )
    ..registerLazySingleton<CabinetMessagingApi>(
      () => CabinetMessagingApi(gi()),
    )
    ..registerLazySingleton<CabinetAppointmentsApi>(
      () => CabinetAppointmentsApi(gi()),
    )
    ..registerLazySingleton<WaitingRoomApi>(
      () => WaitingRoomApi(gi()),
    )
    ..registerLazySingleton<SlotsApi>(
      () => SlotsApi(gi()),
    )
    ..registerLazySingleton<MembersApi>(
      () => MembersApi(gi()),
    )
    ..registerLazySingleton<SecretariatApi>(
      () => SecretariatApi(gi()),
    )
    ..registerLazySingleton<CabinetQuotesApi>(
      () => CabinetQuotesApi(gi()),
    )
    // Repositories
    ..registerLazySingleton<CabinetRepository>(
      () => CabinetRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetDashboardRepository>(
      () => CabinetDashboardRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetPatientsRepository>(
      () => CabinetPatientsRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PatientTagsRepository>(
      () => PatientTagsRepositoryImpl(gi()),
    )
    ..registerLazySingleton<PatientDocumentsRepository>(
      () => PatientDocumentsRepositoryImpl(gi()),
    )
    ..registerLazySingleton<DentalChartRepository>(
      () => DentalChartRepositoryImpl(gi()),
    )
    ..registerLazySingleton<TreatmentPlansRepository>(
      () => TreatmentPlansRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetAgendaRepository>(
      () => CabinetAgendaRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetAppointmentsRepository>(
      () => CabinetAppointmentsRepositoryImpl(gi()),
    )
    ..registerLazySingleton<WaitingRoomRepository>(
      () => WaitingRoomRepositoryImpl(gi()),
    )
    ..registerLazySingleton<WaitingListRepository>(
      () => WaitingListRepositoryImpl(gi()),
    )
    ..registerLazySingleton<SlotsRepository>(
      () => SlotsRepositoryImpl(gi()),
    )
    ..registerLazySingleton<MembersRepository>(
      () => MembersRepositoryImpl(gi()),
    )
    ..registerLazySingleton<SecretariatRepository>(
      () => SecretariatRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetQuotesRepository>(
      () => CabinetQuotesRepositoryImpl(gi()),
    )
    ..registerLazySingleton<CabinetMessageRepository>(
      () => CabinetMessageRepositoryImpl(gi()),
    )
    ..registerLazySingleton<TodayNotesApi>(() => TodayNotesApi(gi()))
    ..registerLazySingleton<TodayNotesRepository>(
      () => TodayNotesRepositoryImpl(gi()),
    );

  // Pro use cases (non-clinical — available to both praticien and secrétariat)
  gi
    ..registerFactory(() => UpdateCabinetUseCase(gi()))
    ..registerFactory(() => GetProDashboardSummaryUseCase(gi()))
    ..registerFactory(() => GetCabinetAgendaUseCase(gi()))
    ..registerFactory(() => ListCabinetPractitionersUseCase(gi()))
    ..registerFactory(() => ConfirmAppointmentUseCase(gi()))
    ..registerFactory(() => ListCabinetAppointmentsUseCase(gi()))
    ..registerFactory(() => CreateCabinetAppointmentUseCase(gi()))
    ..registerFactory(() => RescheduleAppointmentUseCase(gi()))
    ..registerFactory(() => ListCabinetPatientsUseCase(gi()))
    ..registerFactory(() => CreateCabinetPatientUseCase(gi()))
    ..registerFactory(() => ListPatientTagsUseCase(gi()))
    ..registerFactory(() => CreatePatientTagUseCase(gi()))
    ..registerFactory(() => DeletePatientTagUseCase(gi()))
    ..registerFactory(() => ListPatientDocumentsUseCase(gi()))
    ..registerFactory(() => GetDentalChartUseCase(gi()))
    ..registerFactory(() => PutDentalChartUseCase(gi()))
    ..registerFactory(() => ListTreatmentPlansUseCase(gi()))
    ..registerFactory(() => CreateTreatmentPlanUseCase(gi()))
    ..registerFactory(() => CreateTreatmentPhaseUseCase(gi()))
    ..registerFactory(() => GetCabinetPatientUseCase(gi()))
    ..registerFactory(() => UpdatePatientNotesUseCase(gi()))
    ..registerFactory(() => ListWaitingRoomUseCase(gi()))
    ..registerFactory(() => CallNextUseCase(gi()))
    ..registerFactory(() => ListCabinetQuotesUseCase(gi()))
    ..registerFactory(() => GetCabinetQuoteUseCase(gi()))
    ..registerFactory(() => SendCabinetQuoteUseCase(gi()))
    ..registerFactory(() => ListBookableSlotsUseCase(gi()))
    ..registerFactory(() => CreateSlotUseCase(gi()))
    ..registerFactory(() => ListWaitingListUseCase(gi()))
    ..registerFactory(() => OfferSlotToWaitingPatientUseCase(gi()))
    ..registerFactory(() => ListMembersUseCase(gi()))
    ..registerFactory(() => InviteMemberUseCase(gi()))
    ..registerFactory(() => UpdateMemberRoleUseCase(gi()))
    ..registerFactory(() => ListSecretiariatsUseCase(gi()))
    ..registerFactory(() => AddSecretariatUseCase(gi()))
    ..registerFactory(() => ListCabinetConversationsUseCase(gi()))
    ..registerFactory(() => GetCabinetConversationUseCase(gi()))
    ..registerFactory(() => SendMessageCabinetUseCase(gi()))
    ..registerFactory(() => GetTodayNotesUseCase(gi()));

  // Demandes de stock vers les pharmacies (émission côté cabinet, lot B5).
  gi
    ..registerLazySingleton<PharmacyStockApi>(
      () => PharmacyStockApi(gi(), basePath: '/cabinet'),
    )
    ..registerLazySingleton<StockRequestsRepository>(
      () => StockRequestsRepositoryImpl(gi()),
    )
    ..registerFactory(() => ListStockRequestsUseCase(gi()))
    ..registerFactory(() => CreateStockRequestUseCase(gi()));

  if (includeClinical) {
    gi
      ..registerLazySingleton<ConsultationApi>(
        () => ConsultationApi(gi()),
      )
      ..registerLazySingleton<ConsultationRepository>(
        () => ConsultationRepositoryImpl(gi()),
      )
      ..registerFactory(() => StartConsultationUseCase(gi()));
  }
}
