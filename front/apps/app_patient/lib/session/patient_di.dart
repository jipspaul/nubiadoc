import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/account_setup/account_setup_cubit.dart';
import '../features/coverage_setup/coverage_setup_cubit.dart';
import '../features/dependents/dependents_cubit.dart';
import '../features/consents/consents_cubit.dart';
import '../features/notification_prefs/notification_prefs_cubit.dart';
import '../features/appointments/appointments_bloc.dart';
import '../features/dashboard/dashboard_bloc.dart';
import '../features/signup/signup_cubit.dart';
import '../features/forgot_password/forgot_password_cubit.dart';
import '../features/reset_password/reset_password_cubit.dart';
import '../features/documents/documents_bloc.dart';
import '../features/financial/financial_bloc.dart';
import '../features/mes_rdv/mes_rdv_bloc.dart';
import '../features/messaging/messaging_bloc.dart';
import '../features/home/home_bloc.dart';
import '../features/notifications/notifications_bloc.dart';
import '../features/oubliettes/oubliettes_bloc.dart';
import '../features/pharmacy/my_pharmacy_cubit.dart';
import '../features/pharmacy/pharmacy_search_cubit.dart';
import '../features/pharmacy_orders/orders_bloc.dart';
import '../features/pharmacy_orders/send_prescription_cubit.dart';
import '../features/profile/profile_bloc.dart';
import '../features/reviews/reviews_bloc.dart';
import 'auth_cubit.dart';

/// Registers patient-app blocs/cubits on top of registerCore + registerData.
void registerPatient(GetIt gi) {
  gi.registerFactory<MyPharmacyCubit>(
    () => MyPharmacyCubit(
      getMyPharmacy: gi<GetMyPharmacyUseCase>(),
      setMyPharmacy: gi<SetMyPharmacyUseCase>(),
    ),
  );

  gi.registerFactory<PharmacySearchCubit>(
    () => PharmacySearchCubit(search: gi<SearchPharmaciesUseCase>()),
  );

  gi.registerFactory<PatientOrdersBloc>(
    () => PatientOrdersBloc(list: gi<ListPatientPharmacyOrdersUseCase>()),
  );

  gi.registerFactory<PatientOrderDetailCubit>(
    () => PatientOrderDetailCubit(
      get: gi<GetPatientPharmacyOrderUseCase>(),
      watch: gi<WatchPatientPharmacyOrderUseCase>(),
      pickupToken: gi<GetPickupTokenUseCase>(),
      cancel: gi<CancelPharmacyOrderUseCase>(),
    ),
  );

  gi.registerFactory<SendPrescriptionCubit>(
    () => SendPrescriptionCubit(
      listPrescriptions: gi<ListMyPrescriptionsUseCase>(),
      getMyPharmacy: gi<GetMyPharmacyUseCase>(),
      createOrder: gi<CreatePharmacyOrderUseCase>(),
    ),
  );

  gi.registerLazySingleton<AuthCubit>(
    () => AuthCubit(
      login: gi<LoginUseCase>(),
      getMe: gi<GetMeUseCase>(),
      logout: gi<LogoutUseCase>(),
      tokenStorage: gi<TokenStorage>(),
      deviceRegistration: gi<DeviceRegistrationService>(),
    ),
  );

  gi.registerFactory<SignupCubit>(
    () => SignupCubit(
      register: gi<RegisterUseCase>(),
      authCubit: gi<AuthCubit>(),
    ),
  );

  gi.registerFactory<ForgotPasswordCubit>(
    () => ForgotPasswordCubit(forgotPassword: gi<ForgotPasswordUseCase>()),
  );

  gi.registerFactory<ResetPasswordCubit>(
    () => ResetPasswordCubit(resetPassword: gi<ResetPasswordUseCase>()),
  );

  gi.registerFactory<AccountSetupCubit>(
    () => AccountSetupCubit(updateAccount: gi<UpdateAccountUseCase>()),
  );

  gi.registerFactory<CoverageSetupCubit>(
    () => CoverageSetupCubit(updateCoverage: gi<UpdateCoverageUseCase>()),
  );

  gi.registerFactory<DashboardBloc>(
    () => DashboardBloc(getDashboardSummary: gi<GetDashboardSummaryUseCase>()),
  );

  gi.registerFactory<AppointmentsBloc>(
    () => AppointmentsBloc(
      searchProviders: gi<SearchProvidersUseCase>(),
      searchSlots: gi<SearchSlotsUseCase>(),
      holdSlot: gi<HoldSlotUseCase>(),
      confirmBooking: gi<ConfirmBookingUseCase>(),
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
    () => ProfileBloc(
      getAccount: gi<GetAccountUseCase>(),
      userSettings: gi<UserSettingsRepository>(),
      notificationRepo: gi<NotificationRepository>(),
    ),
  );

  gi.registerFactory<DependentsCubit>(
    () => DependentsCubit(
      list: gi<ListDependentsUseCase>(),
      add: gi<AddDependentUseCase>(),
      remove: gi<DeleteDependentUseCase>(),
    ),
  );

  gi.registerFactory<ConsentsCubit>(
    () => ConsentsCubit(
      list: gi<ListConsentsUseCase>(),
      set: gi<SetConsentUseCase>(),
    ),
  );

  gi.registerFactory<NotificationPrefsCubit>(
    () => NotificationPrefsCubit(
      get: gi<GetNotificationPreferencesUseCase>(),
      update: gi<UpdateNotificationPreferencesUseCase>(),
    ),
  );

  gi.registerFactory<HomeBloc>(
    () => HomeBloc(getDashboardSummary: gi<GetDashboardSummaryUseCase>()),
  );

  gi.registerFactory<FinancialBloc>(
    () => FinancialBloc(
      getPendingQuotes: gi<GetPendingQuotesUseCase>(),
      getQuoteById: gi<GetQuoteByIdUseCase>(),
      initiateSignature: gi<InitiateSignatureUseCase>(),
      initiateDeposit: gi<InitiateDepositUseCase>(),
    ),
  );

  gi.registerFactory<MessagingBloc>(
    () => MessagingBloc(
      getConversations: gi<GetConversationsUseCase>(),
      getMessages: gi<GetConversationMessagesUseCase>(),
      sendMessage: gi<SendMessageUseCase>(),
      markRead: gi<MarkConversationReadUseCase>(),
    ),
  );

  gi.registerFactory<DocumentsBloc>(
    () => DocumentsBloc(
      getDocuments: gi<GetDocumentsUseCase>(),
      getSignedUrl: gi<GetDocumentSignedUrlUseCase>(),
      upload: gi<UploadDocumentUseCase>(),
    ),
  );

  gi.registerFactory<NotificationsBloc>(
    () => NotificationsBloc(repository: gi<NotificationRepository>()),
  );

  gi.registerFactory<ReviewsBloc>(
    () => ReviewsBloc(
      getProviderReviews: gi<GetProviderReviewsUseCase>(),
      submitReview: gi<SubmitReviewUseCase>(),
    ),
  );

  gi.registerFactory<OubliettesBloc>(
    () => OubliettesBloc(getDocuments: gi<GetDocumentsUseCase>()),
  );
}
