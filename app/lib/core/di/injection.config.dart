// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:firebase_messaging/firebase_messaging.dart' as _i892;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:nubia_patient/core/di/injection.dart' as _i700;
import 'package:nubia_patient/core/network/api_client.dart' as _i403;
import 'package:nubia_patient/core/network/auth_interceptor.dart' as _i257;
import 'package:nubia_patient/core/storage/token_storage.dart' as _i685;
import 'package:nubia_patient/core/utils/fcm_service.dart' as _i769;
import 'package:nubia_patient/data/remote/account/account_api.dart' as _i611;
import 'package:nubia_patient/data/remote/auth/auth_api.dart' as _i937;
import 'package:nubia_patient/data/remote/clinical/clinical_session_api.dart'
    as _i182;
import 'package:nubia_patient/data/remote/dashboard/dashboard_api.dart' as _i3;
import 'package:nubia_patient/data/remote/documents/document_api.dart' as _i392;
import 'package:nubia_patient/data/remote/messaging/messaging_api.dart'
    as _i897;
import 'package:nubia_patient/data/remote/notifications/notification_api.dart'
    as _i187;
import 'package:nubia_patient/data/remote/prescriptions/prescription_api.dart'
    as _i634;
import 'package:nubia_patient/data/remote/reviews/review_api.dart' as _i1050;
import 'package:nubia_patient/data/remote/scheduling/scheduling_api.dart'
    as _i242;
import 'package:nubia_patient/data/repositories/account_repository_impl.dart'
    as _i217;
import 'package:nubia_patient/data/repositories/appointment_repository_impl.dart'
    as _i472;
import 'package:nubia_patient/data/repositories/auth_repository_impl.dart'
    as _i151;
import 'package:nubia_patient/data/repositories/clinical_session_repository_impl.dart'
    as _i416;
import 'package:nubia_patient/data/repositories/dashboard_repository_impl.dart'
    as _i731;
import 'package:nubia_patient/data/repositories/document_repository_impl.dart'
    as _i158;
import 'package:nubia_patient/data/repositories/message_repository_impl.dart'
    as _i760;
import 'package:nubia_patient/data/repositories/notification_repository_impl.dart'
    as _i284;
import 'package:nubia_patient/data/repositories/prescription_repository_impl.dart'
    as _i49;
import 'package:nubia_patient/data/repositories/review_repository_impl.dart'
    as _i980;
import 'package:nubia_patient/domain/repositories/account_repository.dart'
    as _i485;
import 'package:nubia_patient/domain/repositories/appointment_repository.dart'
    as _i1003;
import 'package:nubia_patient/domain/repositories/auth_repository.dart'
    as _i993;
import 'package:nubia_patient/domain/repositories/clinical_session_repository.dart'
    as _i1018;
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart'
    as _i744;
import 'package:nubia_patient/domain/repositories/document_repository.dart'
    as _i463;
import 'package:nubia_patient/domain/repositories/message_repository.dart'
    as _i74;
import 'package:nubia_patient/domain/repositories/notification_repository.dart'
    as _i405;
import 'package:nubia_patient/domain/repositories/prescription_repository.dart'
    as _i814;
import 'package:nubia_patient/domain/repositories/review_repository.dart'
    as _i833;
import 'package:nubia_patient/domain/repositories/signature_repository.dart'
    as _i968;
import 'package:nubia_patient/domain/usecases/account/get_coverage_use_case.dart'
    as _i68;
import 'package:nubia_patient/domain/usecases/account/upload_coverage_card_use_case.dart'
    as _i116;
import 'package:nubia_patient/domain/usecases/appointments/book_appointment_use_case.dart'
    as _i945;
import 'package:nubia_patient/domain/usecases/appointments/cancel_appointment_use_case.dart'
    as _i884;
import 'package:nubia_patient/domain/usecases/appointments/checkin_appointment_use_case.dart'
    as _i529;
import 'package:nubia_patient/domain/usecases/appointments/get_appointment_by_id_use_case.dart'
    as _i705;
import 'package:nubia_patient/domain/usecases/appointments/get_appointment_history_use_case.dart'
    as _i478;
import 'package:nubia_patient/domain/usecases/appointments/get_upcoming_appointments_use_case.dart'
    as _i1064;
import 'package:nubia_patient/domain/usecases/appointments/modify_appointment_use_case.dart'
    as _i287;
import 'package:nubia_patient/domain/usecases/auth/get_me_use_case.dart'
    as _i563;
import 'package:nubia_patient/domain/usecases/auth/login_use_case.dart'
    as _i934;
import 'package:nubia_patient/domain/usecases/auth/logout_use_case.dart'
    as _i195;
import 'package:nubia_patient/domain/usecases/auth/register_use_case.dart'
    as _i657;
import 'package:nubia_patient/domain/usecases/clinical/add_act_use_case.dart'
    as _i29;
import 'package:nubia_patient/domain/usecases/clinical/complete_session_use_case.dart'
    as _i1018;
import 'package:nubia_patient/domain/usecases/clinical/get_session_use_case.dart'
    as _i516;
import 'package:nubia_patient/domain/usecases/clinical/remove_act_use_case.dart'
    as _i1022;
import 'package:nubia_patient/domain/usecases/clinical/start_session_use_case.dart'
    as _i394;
import 'package:nubia_patient/domain/usecases/dashboard/get_dashboard_summary_use_case.dart'
    as _i618;
import 'package:nubia_patient/domain/usecases/documents/get_document_signed_url_use_case.dart'
    as _i305;
import 'package:nubia_patient/domain/usecases/documents/get_documents_use_case.dart'
    as _i411;
import 'package:nubia_patient/domain/usecases/messaging/get_conversations_use_case.dart'
    as _i753;
import 'package:nubia_patient/domain/usecases/messaging/mark_conversation_read_use_case.dart'
    as _i237;
import 'package:nubia_patient/domain/usecases/messaging/send_message_use_case.dart'
    as _i451;
import 'package:nubia_patient/domain/usecases/prescription/create_prescription_use_case.dart'
    as _i905;
import 'package:nubia_patient/domain/usecases/prescription/sign_prescription_use_case.dart'
    as _i250;
import 'package:nubia_patient/domain/usecases/reviews/get_provider_reviews_use_case.dart'
    as _i248;
import 'package:nubia_patient/domain/usecases/reviews/submit_review_use_case.dart'
    as _i293;
import 'package:nubia_patient/presentation/features/account/bloc/account_bloc.dart'
    as _i525;
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_bloc.dart'
    as _i847;
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_cancel_bloc.dart'
    as _i180;
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_modify_bloc.dart'
    as _i878;
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart'
    as _i799;
import 'package:nubia_patient/presentation/features/appointments/bloc/checkin_bloc.dart'
    as _i381;
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart'
    as _i787;
import 'package:nubia_patient/presentation/features/clinical/bloc/clinical_session_bloc.dart'
    as _i247;
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_bloc.dart'
    as _i94;
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart'
    as _i957;
import 'package:nubia_patient/presentation/features/home/bloc/dashboard_bloc.dart'
    as _i689;
import 'package:nubia_patient/presentation/features/messaging/bloc/messaging_bloc.dart'
    as _i59;
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart'
    as _i414;
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_settings_cubit.dart'
    as _i423;
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_bloc.dart'
    as _i208;
import 'package:nubia_patient/presentation/features/profile/bloc/profile_bloc.dart'
    as _i736;
import 'package:nubia_patient/presentation/features/reviews/bloc/reviews_bloc.dart'
    as _i30;
import 'package:nubia_patient/presentation/features/signature/bloc/signature_bloc.dart'
    as _i1053;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final registerModule = _$RegisterModule();
    gh.singleton<_i558.FlutterSecureStorage>(
        () => registerModule.secureStorage);
    gh.singleton<_i892.FirebaseMessaging>(
        () => registerModule.firebaseMessaging);
    gh.singleton<_i685.TokenStorage>(
        () => _i685.TokenStorage(gh<_i558.FlutterSecureStorage>()));
    gh.factory<_i257.AuthInterceptor>(
        () => _i257.AuthInterceptor(gh<_i685.TokenStorage>()));
    gh.factory<_i1053.SignatureBloc>(
        () => _i1053.SignatureBloc(gh<_i968.SignatureRepository>()));
    gh.lazySingleton<_i403.ApiClient>(
        () => _i403.ApiClient(gh<_i257.AuthInterceptor>()));
    gh.factory<_i611.AccountApi>(() => _i611.AccountApi(gh<_i403.ApiClient>()));
    gh.factory<_i937.AuthApi>(() => _i937.AuthApi(gh<_i403.ApiClient>()));
    gh.factory<_i182.ClinicalSessionApi>(
        () => _i182.ClinicalSessionApi(gh<_i403.ApiClient>()));
    gh.factory<_i3.DashboardApi>(() => _i3.DashboardApi(gh<_i403.ApiClient>()));
    gh.factory<_i392.DocumentApi>(
        () => _i392.DocumentApi(gh<_i403.ApiClient>()));
    gh.factory<_i897.MessagingApi>(
        () => _i897.MessagingApi(gh<_i403.ApiClient>()));
    gh.factory<_i187.NotificationApi>(
        () => _i187.NotificationApi(gh<_i403.ApiClient>()));
    gh.factory<_i634.PrescriptionApi>(
        () => _i634.PrescriptionApi(gh<_i403.ApiClient>()));
    gh.factory<_i1050.ReviewApi>(() => _i1050.ReviewApi(gh<_i403.ApiClient>()));
    gh.factory<_i242.SchedulingApi>(
        () => _i242.SchedulingApi(gh<_i403.ApiClient>()));
    gh.lazySingleton<_i485.AccountRepository>(
        () => _i217.AccountRepositoryImpl(gh<_i611.AccountApi>()));
    gh.lazySingleton<_i463.DocumentRepository>(
        () => _i158.DocumentRepositoryImpl(gh<_i392.DocumentApi>()));
    gh.lazySingleton<_i405.NotificationRepository>(
        () => _i284.NotificationRepositoryImpl(gh<_i187.NotificationApi>()));
    gh.lazySingleton<_i744.DashboardRepository>(
        () => _i731.DashboardRepositoryImpl(gh<_i3.DashboardApi>()));
    gh.lazySingleton<_i1018.ClinicalSessionRepository>(() =>
        _i416.ClinicalSessionRepositoryImpl(gh<_i182.ClinicalSessionApi>()));
    gh.lazySingleton<_i993.AuthRepository>(() => _i151.AuthRepositoryImpl(
          gh<_i937.AuthApi>(),
          gh<_i685.TokenStorage>(),
        ));
    gh.lazySingleton<_i833.ReviewRepository>(
        () => _i980.ReviewRepositoryImpl(gh<_i1050.ReviewApi>()));
    gh.factory<_i563.GetMeUseCase>(
        () => _i563.GetMeUseCase(gh<_i993.AuthRepository>()));
    gh.factory<_i934.LoginUseCase>(
        () => _i934.LoginUseCase(gh<_i993.AuthRepository>()));
    gh.factory<_i195.LogoutUseCase>(
        () => _i195.LogoutUseCase(gh<_i993.AuthRepository>()));
    gh.factory<_i657.RegisterUseCase>(
        () => _i657.RegisterUseCase(gh<_i993.AuthRepository>()));
    gh.lazySingleton<_i74.MessageRepository>(() => _i760.MessageRepositoryImpl(
          gh<_i897.MessagingApi>(),
          gh<_i392.DocumentApi>(),
        ));
    gh.factory<_i414.NotificationBloc>(
        () => _i414.NotificationBloc(gh<_i405.NotificationRepository>()));
    gh.factory<_i423.NotificationSettingsCubit>(() =>
        _i423.NotificationSettingsCubit(gh<_i405.NotificationRepository>()));
    gh.factory<_i753.GetConversationsUseCase>(
        () => _i753.GetConversationsUseCase(gh<_i74.MessageRepository>()));
    gh.factory<_i237.MarkConversationReadUseCase>(
        () => _i237.MarkConversationReadUseCase(gh<_i74.MessageRepository>()));
    gh.factory<_i451.SendMessageUseCase>(
        () => _i451.SendMessageUseCase(gh<_i74.MessageRepository>()));
    gh.factory<_i59.MessagingBloc>(
        () => _i59.MessagingBloc(gh<_i74.MessageRepository>()));
    gh.factory<_i305.GetDocumentSignedUrlUseCase>(() =>
        _i305.GetDocumentSignedUrlUseCase(gh<_i463.DocumentRepository>()));
    gh.factory<_i411.GetDocumentsUseCase>(
        () => _i411.GetDocumentsUseCase(gh<_i463.DocumentRepository>()));
    gh.factory<_i957.DocumentBloc>(
        () => _i957.DocumentBloc(gh<_i463.DocumentRepository>()));
    gh.lazySingleton<_i814.PrescriptionRepository>(
        () => _i49.PrescriptionRepositoryImpl(gh<_i634.PrescriptionApi>()));
    gh.lazySingleton<_i1003.AppointmentRepository>(
        () => _i472.AppointmentRepositoryImpl(gh<_i242.SchedulingApi>()));
    gh.factory<_i248.GetProviderReviewsUseCase>(
        () => _i248.GetProviderReviewsUseCase(gh<_i833.ReviewRepository>()));
    gh.factory<_i293.SubmitReviewUseCase>(
        () => _i293.SubmitReviewUseCase(gh<_i833.ReviewRepository>()));
    gh.factory<_i30.ReviewsBloc>(() => _i30.ReviewsBloc(
          gh<_i248.GetProviderReviewsUseCase>(),
          gh<_i293.SubmitReviewUseCase>(),
        ));
    gh.factory<_i769.FcmService>(() => _i769.FcmService(
          gh<_i892.FirebaseMessaging>(),
          gh<_i405.NotificationRepository>(),
        ));
    gh.factory<_i618.GetDashboardSummaryUseCase>(() =>
        _i618.GetDashboardSummaryUseCase(gh<_i744.DashboardRepository>()));
    gh.factory<_i29.AddActUseCase>(
        () => _i29.AddActUseCase(gh<_i1018.ClinicalSessionRepository>()));
    gh.factory<_i1018.CompleteSessionUseCase>(() =>
        _i1018.CompleteSessionUseCase(gh<_i1018.ClinicalSessionRepository>()));
    gh.factory<_i516.GetSessionUseCase>(
        () => _i516.GetSessionUseCase(gh<_i1018.ClinicalSessionRepository>()));
    gh.factory<_i1022.RemoveActUseCase>(
        () => _i1022.RemoveActUseCase(gh<_i1018.ClinicalSessionRepository>()));
    gh.factory<_i394.StartSessionUseCase>(() =>
        _i394.StartSessionUseCase(gh<_i1018.ClinicalSessionRepository>()));
    gh.factory<_i68.GetCoverageUseCase>(
        () => _i68.GetCoverageUseCase(gh<_i485.AccountRepository>()));
    gh.factory<_i116.UploadCoverageCardUseCase>(
        () => _i116.UploadCoverageCardUseCase(gh<_i485.AccountRepository>()));
    gh.factory<_i525.AccountBloc>(
        () => _i525.AccountBloc(gh<_i485.AccountRepository>()));
    gh.factory<_i945.BookAppointmentUseCase>(
        () => _i945.BookAppointmentUseCase(gh<_i1003.AppointmentRepository>()));
    gh.factory<_i884.CancelAppointmentUseCase>(() =>
        _i884.CancelAppointmentUseCase(gh<_i1003.AppointmentRepository>()));
    gh.factory<_i529.CheckinAppointmentUseCase>(() =>
        _i529.CheckinAppointmentUseCase(gh<_i1003.AppointmentRepository>()));
    gh.factory<_i705.GetAppointmentByIdUseCase>(() =>
        _i705.GetAppointmentByIdUseCase(gh<_i1003.AppointmentRepository>()));
    gh.factory<_i478.GetAppointmentHistoryUseCase>(() =>
        _i478.GetAppointmentHistoryUseCase(gh<_i1003.AppointmentRepository>()));
    gh.factory<_i1064.GetUpcomingAppointmentsUseCase>(() =>
        _i1064.GetUpcomingAppointmentsUseCase(
            gh<_i1003.AppointmentRepository>()));
    gh.factory<_i287.ModifyAppointmentUseCase>(() =>
        _i287.ModifyAppointmentUseCase(gh<_i1003.AppointmentRepository>()));
    gh.factory<_i787.AuthBloc>(
        () => _i787.AuthBloc(gh<_i993.AuthRepository>()));
    gh.factory<_i736.ProfileBloc>(
        () => _i736.ProfileBloc(gh<_i993.AuthRepository>()));
    gh.factory<_i180.AppointmentCancelBloc>(() =>
        _i180.AppointmentCancelBloc(gh<_i884.CancelAppointmentUseCase>()));
    gh.factory<_i905.CreatePrescriptionUseCase>(() =>
        _i905.CreatePrescriptionUseCase(gh<_i814.PrescriptionRepository>()));
    gh.factory<_i250.SignPrescriptionUseCase>(() =>
        _i250.SignPrescriptionUseCase(gh<_i814.PrescriptionRepository>()));
    gh.factory<_i689.DashboardBloc>(
        () => _i689.DashboardBloc(gh<_i618.GetDashboardSummaryUseCase>()));
    gh.factory<_i247.ClinicalSessionBloc>(() => _i247.ClinicalSessionBloc(
          gh<_i394.StartSessionUseCase>(),
          gh<_i516.GetSessionUseCase>(),
          gh<_i29.AddActUseCase>(),
          gh<_i1022.RemoveActUseCase>(),
          gh<_i1018.CompleteSessionUseCase>(),
        ));
    gh.factory<_i847.AppointmentBloc>(() => _i847.AppointmentBloc(
          gh<_i1064.GetUpcomingAppointmentsUseCase>(),
          gh<_i478.GetAppointmentHistoryUseCase>(),
        ));
    gh.factory<_i878.AppointmentModifyBloc>(() =>
        _i878.AppointmentModifyBloc(gh<_i287.ModifyAppointmentUseCase>()));
    gh.factory<_i381.CheckinBloc>(
        () => _i381.CheckinBloc(gh<_i529.CheckinAppointmentUseCase>()));
    gh.factory<_i94.CoverageBloc>(() => _i94.CoverageBloc(
          gh<_i68.GetCoverageUseCase>(),
          gh<_i116.UploadCoverageCardUseCase>(),
        ));
    gh.factory<_i799.BookingBloc>(() => _i799.BookingBloc(
          gh<_i1064.GetUpcomingAppointmentsUseCase>(),
          gh<_i945.BookAppointmentUseCase>(),
        ));
    gh.factory<_i208.PrescriptionBloc>(() => _i208.PrescriptionBloc(
          gh<_i905.CreatePrescriptionUseCase>(),
          gh<_i250.SignPrescriptionUseCase>(),
        ));
    return this;
  }
}

class _$RegisterModule extends _i700.RegisterModule {}
