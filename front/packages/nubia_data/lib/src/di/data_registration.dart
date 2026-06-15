import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../remote/account/account_api.dart';
import '../remote/auth/auth_api.dart';
import '../remote/billing/billing_api.dart';
import '../remote/clinical/clinical_session_api.dart';
import '../remote/dashboard/dashboard_api.dart';
import '../remote/documents/document_api.dart';
import '../remote/messaging/messaging_api.dart';
import '../remote/notifications/notification_api.dart';
import '../remote/prescriptions/prescription_api.dart';
import '../remote/reviews/review_api.dart';
import '../remote/scheduling/scheduling_api.dart';
import '../repositories/account_repository_impl.dart';
import '../repositories/appointment_repository_impl.dart';
import '../repositories/auth_repository_impl.dart';
import '../repositories/billing_repository_impl.dart';
import '../repositories/clinical_session_repository_impl.dart';
import '../repositories/dashboard_repository_impl.dart';
import '../repositories/document_repository_impl.dart';
import '../repositories/message_repository_impl.dart';
import '../repositories/notification_repository_impl.dart';
import '../repositories/prescription_repository_impl.dart';
import '../repositories/review_repository_impl.dart';

/// Registers the data layer: Dio APIs, repository implementations and use cases.
///
/// Call after `registerCore(gi)` so that [ApiClient]/[TokenStorage] are
/// available. GetIt resolves each constructor argument by type via `gi()`.
///
/// [includeClinical] gates the clinical + prescription stacks. The secretariat
/// app passes `false`, guaranteeing no clinical repository/use case is ever
/// registered in its container (no code path to clinical data).
void registerData(GetIt gi, {bool includeClinical = true}) {
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
    ..registerLazySingleton<SchedulingApi>(() => SchedulingApi(gi()));

  // --- Repositories ---------------------------------------------------------
  gi
    ..registerLazySingleton<AccountRepository>(
      () => AccountRepositoryImpl(gi()),
    )
    ..registerLazySingleton<AppointmentRepository>(
      () => AppointmentRepositoryImpl(gi()),
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
    );

  // --- Use cases ------------------------------------------------------------
  _registerUseCases(gi);

  if (includeClinical) {
    _registerClinical(gi);
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
    ..registerFactory(() => GetCoverageUseCase(gi()))
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
    // messaging
    ..registerFactory(() => GetConversationsUseCase(gi()))
    ..registerFactory(() => MarkConversationReadUseCase(gi()))
    ..registerFactory(() => SendMessageUseCase(gi()))
    // reviews
    ..registerFactory(() => GetProviderReviewsUseCase(gi()))
    ..registerFactory(() => SubmitReviewUseCase(gi()));
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
