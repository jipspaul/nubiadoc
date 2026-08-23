import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../features/agenda/agenda_page.dart';
import '../features/admin_membres/admin_membres_bloc.dart';
import '../features/admin_membres/admin_membres_page.dart';
import '../features/admin_secretariats/admin_secretariats_bloc.dart';
import '../features/admin_secretariats/admin_secretariats_page.dart';
import '../features/appointment_motifs/appointment_motifs_bloc.dart';
import '../features/appointment_motifs/appointment_motifs_page.dart';
import '../features/appointments/appointments_bloc.dart';
import '../features/appointments/appointments_page.dart';
import '../features/bookable_slots/bookable_slots_bloc.dart';
import '../features/bookable_slots/bookable_slots_page.dart';
import '../features/cabinet_team_messages/cabinet_team_messages_page.dart';
import '../features/cabinet_messaging/cabinet_messaging_bloc.dart';
import '../features/cabinet_messaging/cabinet_messaging_event.dart';
import '../features/cabinet_messaging/cabinet_messaging_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/devis/devis_bloc.dart';
import '../features/devis/devis_detail_page.dart';
import '../features/devis/devis_page.dart';
import '../features/login/login_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/patients/patient_quick_create_page.dart';
import '../features/patients/patients_bloc.dart';
import '../features/patients/patients_page.dart';
import '../features/stock/stock_bloc.dart';
import '../features/stock/stock_page.dart';
import '../features/waiting_list/waiting_list_bloc.dart';
import '../features/waiting_list/waiting_list_page.dart';
import '../features/cabinet_stats/cabinet_stats_bloc.dart';
import '../features/cabinet_stats/cabinet_stats_event.dart';
import '../features/cabinet_stats/cabinet_stats_page.dart';
import '../features/cabinet_payouts/cabinet_payouts_bloc.dart';
import '../features/cabinet_payouts/cabinet_payouts_event.dart';
import '../features/cabinet_payouts/cabinet_payouts_page.dart';
import '../features/audit_log/audit_log_bloc.dart';
import '../features/audit_log/audit_log_event.dart';
import '../features/audit_log/audit_log_page.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
import '../features/waiting_room/waiting_room_page.dart';

class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const onboard = '/onboard';
  static const home = '/';
  static const agenda = '/agenda';
  static const bookableSlots = '/bookable-slots';
  static const a2uiDemo = '/a2ui-demo';
  static const salleAttente = '/salle-attente';
  static const cabinetStats = '/cabinet-stats';
  static const cabinetPayouts = '/cabinet-payouts';
  static const auditLog = '/audit-log';

  static const patients = '/patients';
  static const patientNew = '/patients/new';
  static const appointments = '/appointments';
  static const listeAttente = '/liste-attente';
  static const devis = '/devis';
  static const devisDetail = '/devis/:id';
  static const stock = '/stock';
  static const messages = '/messages';
  static const teamMessages = '/team-messages';
  static const adminMembres = '/admin-membres';
  static const adminSecretariats = '/admin-secretariats';
  static const appointmentMotifs = '/appointment-motifs';

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
        authRoutes: const {login, onboard, splash},
      ),
      // Route inconnue (deep-link périmé, bookmark cassé) : sans errorBuilder,
      // go_router affiche son écran par défaut avec l'exception brute
      // (« GoException: no routes for location: … ») — #3894.
      errorBuilder: (context, state) => Scaffold(
        body: NubiaEmptyState(
          icon: Icons.search_off,
          title: 'Page introuvable',
          subtitle: 'Le lien que vous avez suivi n\'existe plus ou a changé.',
          action: FilledButton(
            onPressed: () => context.go(home),
            child: const Text('Retour à l\'accueil'),
          ),
        ),
      ),
      routes: [
        GoRoute(
          path: splash,
          builder: (_, __) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: login, builder: (_, __) => const LoginPage()),
        GoRoute(
          path: onboard,
          builder: (_, state) => OnboardingPage(
            invitationToken: state.uri.queryParameters['invitation_token'],
          ),
        ),
        // Routes secondaires — pas des destinations de nav (absentes de
        // `ProConfig.shellConfig.destinations`) : deep-links/pushes ponctuels
        // qui restent volontairement hors du `StatefulShellRoute` ci-dessous
        // (#5154 — décision documentée dans `README.md`).
        // #5152 — route de démonstration : ne jamais l'enregistrer en
        // release, sous peine d'être atteignable par URL en production.
        if (kDebugMode)
          GoRoute(
            path: a2uiDemo,
            builder: (_, __) => const A2uiDemoPage(),
          ),
        GoRoute(
          path: patientNew,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<PatientsBloc>(),
            child: const PatientQuickCreatePage(),
          ),
        ),
        GoRoute(
          path: appointments,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<AppointmentsBloc>(),
            child: const AppointmentsPage(),
          ),
        ),
        // #5154 — le `ProShell` enveloppe désormais TOUTES les destinations
        // de nav via `StatefulShellRoute.indexedStack` (une branche par
        // entrée de `ProConfig.shellConfig.destinations`, même ordre) : la
        // barre de navigation reste visible quelle que soit la route et
        // l'URL reflète toujours la destination active. Chaque branche
        // réutilise directement l'écran « page complète » existant (son
        // propre `Scaffold`/`AppBar`/FAB, ex. `AdminSecretariatsPage`) —
        // `ProShell` ne fournit son propre `AppBar` générique que pour les
        // destinations qui n'en ont pas (dashboard, agenda), afin de ne
        // jamais dupliquer de barre de titre.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              SecretariatShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: home, builder: (_, __) => const DashboardBody()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: salleAttente,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<WaitingRoomBloc>(),
                  child: const WaitingRoomPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: listeAttente,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<WaitingListBloc>(),
                  child: const WaitingListPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: agenda, builder: (_, __) => const AgendaPage()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: bookableSlots,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<BookableSlotsBloc>(),
                  child: const BookableSlotsPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: patients,
                builder: (_, state) => BlocProvider(
                  create: (_) => GetIt.instance<PatientsBloc>(),
                  child: PatientsPage(openPatientId: state.extra as String?),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: devis,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<DevisBloc>(),
                  child: const DevisPage(),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => BlocProvider(
                      create: (_) => GetIt.instance<DevisBloc>(),
                      child: DevisDetailPage(
                        id: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: stock,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<StockBloc>(),
                  child: const StockPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: messages,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<CabinetMessagingBloc>()
                    ..add(const CabinetMessagingConversationsLoadRequested()),
                  child: const CabinetMessagingPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: teamMessages,
                builder: (_, __) => const CabinetTeamMessagesPage(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: appointmentMotifs,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<AppointmentMotifsBloc>(),
                  child: const AppointmentMotifsPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: adminMembres,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<AdminMembresBloc>(),
                  child: const AdminMembresPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: adminSecretariats,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<AdminSecretariatsBloc>(),
                  child: const AdminSecretariatsPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: cabinetStats,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<CabinetStatsBloc>()
                    ..add(const CabinetStatsLoadRequested()),
                  child: const CabinetStatsPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: cabinetPayouts,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<CabinetPayoutsBloc>()
                    ..add(const CabinetPayoutsLoadRequested()),
                  child: const CabinetPayoutsPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: auditLog,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<AuditLogBloc>()
                    ..add(const AuditLogLoadRequested()),
                  child: const AuditLogPage(),
                ),
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
