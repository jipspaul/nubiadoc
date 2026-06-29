import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../features/appointments/appointments_bloc.dart';
import '../features/dashboard/dashboard_bloc.dart';
import '../features/signup/signup_cubit.dart';
import '../features/documents/documents_bloc.dart';
import '../features/financial/financial_bloc.dart';
import '../features/mes_rdv/mes_rdv_bloc.dart';
import '../features/messaging/messaging_bloc.dart';
import '../features/home/home_bloc.dart';
import '../features/notifications/notifications_bloc.dart';
import '../features/oubliettes/oubliettes_bloc.dart';
import '../features/profile/profile_bloc.dart';
import '../features/reviews/reviews_bloc.dart';
import 'auth_cubit.dart';

/// Registers patient-app blocs/cubits on top of registerCore + registerData.
void registerPatient(GetIt gi) {
  gi.registerFactory<AuthCubit>(
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

  gi.registerFactory<DashboardBloc>(
    () => DashboardBloc(getDashboardSummary: gi<GetDashboardSummaryUseCase>()),
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
    () => ProfileBloc(
      getAccount: gi<GetAccountUseCase>(),
      userSettings: gi<UserSettingsRepository>(),
      notificationRepo: gi<NotificationRepository>(),
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

  gi.registerFactory<OubliettesBloc>(() => OubliettesBloc());
}
