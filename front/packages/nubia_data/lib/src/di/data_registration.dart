import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../cache/appointments_cache.dart';
import '../cache/drift/drift_appointments_cache.dart';
import '../cache/drift/nubia_database.dart';
import '../remote/account/account_api.dart';
import '../remote/auth/auth_api.dart';
import '../remote/billing/billing_api.dart';
import '../remote/cabinet_agenda/cabinet_agenda_api.dart';
import '../remote/cabinet_appointments/cabinet_appointments_api.dart';
import '../remote/cabinet_messaging/cabinet_messaging_api.dart';
import '../remote/cabinet_patients/cabinet_patients_api.dart';
import '../remote/cabinet_quotes/cabinet_quotes_api.dart';
import '../remote/clinical/clinical_session_api.dart';
import '../remote/consultation/consultation_api.dart';
import '../remote/dashboard/dashboard_api.dart';
import '../remote/documents/document_api.dart';
import '../remote/members/members_api.dart';
import '../remote/messaging/messaging_api.dart';
import '../remote/notifications/notification_api.dart';
import '../remote/prescriptions/prescription_api.dart';
import '../remote/reviews/review_api.dart';
import '../remote/scheduling/scheduling_api.dart';
import '../remote/search/search_api.dart';
import '../remote/secretariat/secretariat_api.dart';
import '../remote/slots/slots_api.dart';
import '../remote/waiting_room/waiting_room_api.dart';
import '../repositories/account_repository_impl.dart';
import '../repositories/search_repository_impl.dart';
import '../repositories/appointment_repository_impl.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/billing_repository_impl.dart';
import '../repositories/cabinet_agenda_repository_impl.dart';
import '../repositories/cabinet_appointments_repository_impl.dart';
import '../repositories/cabinet_message_repository_impl.dart';
import '../repositories/cabinet_patients_repository_impl.dart';
import '../repositories/cabinet_quotes_repository_impl.dart';
import '../repositories/cached_appointments_repository_impl.dart';
import '../repositories/clinical_session_repository_impl.dart';
import '../repositories/consultation_repository_impl.dart';
import '../repositories/dashboard_repository_impl.dart';
import '../repositories/document_repository_impl.dart';
import '../repositories/members_repository_impl.dart';
import '../repositories/message_repository_impl.dart';
import '../repositories/notification_repository_impl.dart';
import '../repositories/prescription_repository_impl.dart';
import '../repositories/review_repository_impl.dart';
import '../repositories/secretariat_repository_impl.dart';
import '../repositories/slots_repository_impl.dart';
import '../repositories/waiting_room_repository_impl.dart';

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
void registerData(
  GetIt gi, {
  bool includeClinical = true,
  bool includePro = false,
  bool useCache = false,
}) {
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
      () => AuthRepositoryImpl(gi(), gi()),
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

  // --- Use cases ------------------------------------------------------------
  _registerUseCases(gi);

  if (includeClinical) {
    _registerClinical(gi);
  }

  if (includePro) {
    _registerPro(gi, includeClinical: includeClinical);
  }
}

void _registerUseCases(GetIt gi) {
  gi
    // auth
    ..registerFactory(() => LoginUseCase(gi()))
    ..registerFactory(() => LogoutUseCase(gi()))
    ..registerFactory(() => RegisterUseCase(gi()))
    ..registerFactory(() => GetMeUseCase(gi()))
    // account
    ..registerFactory(() => GetAccountUseCase(gi()))
    ..registerFactory(() => GetCoverageUseCase(gi()))
    ..registerFactory(() => GetNotificationPreferencesUseCase(gi()))
    ..registerFactory(() => ListConsentsUseCase(gi()))
    ..registerFactory(() => ListDependentsUseCase(gi()))
    ..registerFactory(() => UploadCoverageCardUseCase(gi()))
    // appointments
    ..registerFactory(() => BookAppointmentUseCase(gi()))
    ..registerFactory(() => CancelAppointmentUseCase(gi()))
    ..registerFactory(() => CheckinAppointmentUseCase(gi()))
    ..registerFactory(() => GetAppointmentByIdUseCase(gi()))
    ..registerFactory(() => GetAppointmentHistoryUseCase(gi()))
    ..registerFactory(() => GetUpcomingAppointmentsUseCase(gi()))
    ..registerFactory(() => ModifyAppointmentUseCase(gi()))
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
    ..registerFactory(() => SearchProvidersUseCase(gi()))
    ..registerFactory(() => SearchSlotsUseCase(gi()))
    ..registerFactory(() => HoldSlotUseCase(gi()));
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
    ..registerFactory(() => RemoveActUseCase(gi()))
    ..registerFactory(() => StartSessionUseCase(gi()))
    // prescription use cases
    ..registerFactory(() => CreatePrescriptionUseCase(gi()))
    ..registerFactory(() => SignPrescriptionUseCase(gi()));
}

/// Registers the pro/cabinet data stack.
///
/// [includeClinical] controls whether [ConsultationApi] and
/// [ConsultationRepository] are registered — secretariat apps pass `false`.
void _registerPro(GetIt gi, {bool includeClinical = true}) {
  gi
    // APIs
    ..registerLazySingleton<CabinetPatientsApi>(
      () => CabinetPatientsApi(gi()),
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
    ..registerLazySingleton<CabinetPatientsRepository>(
      () => CabinetPatientsRepositoryImpl(gi()),
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
    );

  // Pro use cases (non-clinical — available to both praticien and secrétariat)
  gi
    ..registerFactory(() => ListCabinetPatientsUseCase(gi()))
    ..registerFactory(() => GetCabinetPatientUseCase(gi()))
    ..registerFactory(() => ListWaitingRoomUseCase(gi()))
    ..registerFactory(() => CallNextUseCase(gi()))
    ..registerFactory(() => ListMembersUseCase(gi()))
    ..registerFactory(() => InviteMemberUseCase(gi()))
    ..registerFactory(() => UpdateMemberRoleUseCase(gi()))
    ..registerFactory(() => ListSecretiariatsUseCase(gi()))
    ..registerFactory(() => AddSecretariatUseCase(gi()));

  if (includeClinical) {
    gi
      ..registerLazySingleton<ConsultationApi>(
        () => ConsultationApi(gi()),
      )
      ..registerLazySingleton<ConsultationRepository>(
        () => ConsultationRepositoryImpl(gi()),
      );
  }

  // cabinet messaging use cases
  gi
    ..registerFactory(() => ListCabinetConversationsUseCase(gi()))
    ..registerFactory(() => GetCabinetConversationUseCase(gi()))
    ..registerFactory(() => SendMessageCabinetUseCase(gi()));
}
