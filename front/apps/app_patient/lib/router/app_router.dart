import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';
import 'package:nubia_core/nubia_core.dart';

import '../features/appointments/appointments_bloc.dart';
import '../features/appointments/appointments_page.dart';
import '../features/booking/book_appointment_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/financial/financial_bloc.dart';
import '../features/financial/financial_event.dart';
import '../features/financial/financial_page.dart';
import '../features/documents/documents_page.dart';
import '../features/account_setup/account_setup_cubit.dart';
import '../features/account_setup/account_setup_page.dart';
import '../features/coverage_setup/coverage_setup_cubit.dart';
import '../features/coverage_setup/coverage_setup_page.dart';
import '../features/login/login_page.dart';
import '../features/forgot_password/forgot_password_cubit.dart';
import '../features/forgot_password/forgot_password_page.dart';
import '../features/reset_password/reset_password_cubit.dart';
import '../features/reset_password/reset_password_page.dart';
import '../features/signup/signup_cubit.dart';
import '../features/signup/signup_page.dart';
import '../features/mes_rdv/mes_rdv_page.dart';
import '../features/mes_rdv/prepare_rdv_page.dart';
import '../features/notifications/notifications_bloc.dart';
import '../features/notifications/notifications_event.dart';
import '../features/notifications/notifications_page.dart';
import '../features/oubliettes/oubliettes_bloc.dart';
import '../features/oubliettes/oubliettes_page.dart';
import '../features/profile/profile_bloc.dart';
import '../features/profile/profile_event.dart';
import '../features/pharmacy/my_pharmacy_page.dart';
import '../features/pharmacy/pharmacy_search_page.dart';
import '../features/referring_doctor/referring_doctor_page.dart';
import '../features/referring_doctor/referring_doctor_search_page.dart';
import '../features/pharmacy_orders/order_detail_page.dart';
import '../features/pharmacy_orders/orders_page.dart';
import '../features/pharmacy_orders/send_prescription_page.dart';
import '../features/profile/profile_page.dart';
import '../features/dependents/dependents_page.dart';
import '../features/consents/consents_page.dart';
import '../features/notification_prefs/notification_prefs_page.dart';
import '../features/messaging/messaging_bloc.dart';
import '../features/messaging/messaging_event.dart';
import '../features/messaging/messaging_page.dart';
import '../features/reviews/reviews_bloc.dart';
import '../features/reviews/reviews_event.dart';
import '../features/reviews/reviews_page.dart';

/// Patient router. Route names are app-owned; the auth guard is the shared
/// [buildAuthGuard] from nubia_core.
class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const signup = '/signup';
  static const accountSetup = '/account-setup';
  static const coverageSetup = '/coverage-setup';
  static const home = '/';
  static const a2uiDemo = '/a2ui-demo';
  static const appointments = '/appointments';
  static const mesRdv = '/mes-rdv';
  static const documents = '/documents';
  static const financial = '/financial';
  static const profile = '/profile';
  static const profileDependents = '/profile/dependents';
  static const profileConsents = '/profile/consents';
  static const profileNotifications = '/profile/notifications';
  static const profileReferringDoctor = '/profile/referring-doctor';
  static const messaging = '/messaging';
  static const reviews = '/reviews';
  static const notifications = '/notifications';
  static const oubliettes = '/oubliettes';
  static const prepareRdv = '/rdv/:id/prepare';
  static const book = '/book';

  static GoRouter create(RouterNotifier notifier) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: notifier,
      // PostHog: capture les events $screen à chaque navigation.
      observers: [PosthogObserver()],
      redirect: buildAuthGuard(
        notifier,
        loginRoute: login,
        homeRoute: home,
        splashRoute: splash,
        authRoutes: const {
          login,
          splash,
          signup,
          forgotPassword,
          resetPassword
        },
        // signup authentifie l'utilisateur en cours de flow (restore() après
        // le 201) puis navigue explicitement vers /account-setup : ne pas le
        // renvoyer vers home entre-temps (course avec le listener du
        // RouterNotifier — même fix que praticien/register-pro, #3195).
        guestOnlyRoutes: const {login, splash},
      ),
      routes: [
        GoRoute(
          path: splash,
          builder: (_, __) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: login, builder: (_, __) => const LoginPage()),
        GoRoute(
          path: forgotPassword,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<ForgotPasswordCubit>(),
            child: const ForgotPasswordPage(),
          ),
        ),
        GoRoute(
          path: resetPassword,
          builder: (_, state) => BlocProvider(
            create: (_) => GetIt.instance<ResetPasswordCubit>(),
            child: ResetPasswordPage(token: state.uri.queryParameters['token']),
          ),
        ),
        GoRoute(
          path: signup,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<SignupCubit>(),
            child: const SignupPage(),
          ),
        ),
        GoRoute(
          path: accountSetup,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<AccountSetupCubit>(),
            child: const AccountSetupPage(),
          ),
        ),
        GoRoute(
          path: coverageSetup,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<CoverageSetupCubit>(),
            child: const CoverageSetupPage(),
          ),
        ),
        GoRoute(path: home, builder: (_, __) => const DashboardPage()),
        GoRoute(
          path: '/pharmacy',
          builder: (_, __) => const MyPharmacyPage(),
        ),
        GoRoute(
          path: '/pharmacy/search',
          builder: (_, state) => PharmacySearchPage(
            selectionMode: state.uri.queryParameters['selection'] == 'true',
          ),
        ),
        GoRoute(
          path: profileReferringDoctor,
          builder: (_, __) => const ReferringDoctorPage(),
        ),
        GoRoute(
          path: '$profileReferringDoctor/search',
          builder: (_, __) => const ReferringDoctorSearchPage(),
        ),
        GoRoute(
          path: '/pharmacy/send',
          builder: (_, __) => const SendPrescriptionPage(),
        ),
        GoRoute(
          path: '/pharmacy/orders',
          builder: (_, __) => const PatientOrdersPage(),
        ),
        GoRoute(
          path: '/pharmacy/orders/:id',
          builder: (_, state) =>
              PatientOrderDetailPage(orderId: state.pathParameters['id']!),
        ),
        GoRoute(path: a2uiDemo, builder: (_, __) => const A2uiDemoPage()),
        GoRoute(
          path: appointments,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<AppointmentsBloc>(),
            child: Scaffold(
              appBar: AppBar(title: const Text('Prendre un rendez-vous')),
              body: const AppointmentsPage(),
            ),
          ),
        ),
        GoRoute(
          path: mesRdv,
          builder: (context, __) => Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('book_rdv_fab'),
              onPressed: () => context.go(AppRouter.book),
              icon: const Icon(Icons.add),
              label: const Text('Booker un RDV'),
            ),
            body: const MesRdvPage(),
          ),
        ),
        GoRoute(
          path: documents,
          builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('Mes documents')),
            body: const DocumentsPage(),
          ),
        ),
        GoRoute(
          path: financial,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<FinancialBloc>()
              ..add(const FinancialLoadRequested()),
            child: Scaffold(
              appBar: AppBar(title: const Text('Mes devis')),
              body: const FinancialPage(),
            ),
          ),
        ),
        GoRoute(
          path: profile,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<ProfileBloc>()
              ..add(const ProfileLoadRequested()),
            child: Scaffold(
              appBar: AppBar(title: const Text('Mon profil')),
              body: const ProfilePage(),
            ),
          ),
        ),
        GoRoute(
          path: profileDependents,
          builder: (_, __) => const DependentsPage(),
        ),
        GoRoute(
          path: profileConsents,
          builder: (_, __) => const ConsentsPage(),
        ),
        GoRoute(
          path: profileNotifications,
          builder: (_, __) => const NotificationPrefsPage(),
        ),
        GoRoute(
          path: messaging,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<MessagingBloc>()
              ..add(const MessagingConversationsLoadRequested()),
            child: Scaffold(
              appBar: AppBar(title: const Text('Messages')),
              body: const MessagingPage(),
            ),
          ),
        ),
        GoRoute(
          path: reviews,
          builder: (context, state) {
            final providerId = state.uri.queryParameters['providerId'] ?? '';
            return BlocProvider(
              create: (_) => GetIt.instance<ReviewsBloc>()
                ..add(ReviewsLoadRequested(providerId)),
              child: Scaffold(
                appBar: AppBar(title: const Text('Avis')),
                body: const ReviewsPage(),
              ),
            );
          },
        ),
        GoRoute(
          path: notifications,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<NotificationsBloc>()
              ..add(const NotificationsLoadRequested()),
            child: Scaffold(
              key: const Key('notifications_scaffold'),
              appBar: AppBar(title: const Text('Notifications')),
              body: const NotificationsPage(),
            ),
          ),
        ),
        GoRoute(
          path: oubliettes,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<OubliettesBloc>()
              ..add(const OubliettesLoadRequested()),
            child: Scaffold(
              appBar: AppBar(title: const Text('Oubliettes')),
              body: const OubliettesPage(),
            ),
          ),
        ),
        GoRoute(
          path: prepareRdv,
          builder: (_, state) => PrepareRdvPage(
            appointmentId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: book,
          builder: (_, __) => const BookAppointmentPage(),
        ),
      ],
    );
  }
}
