import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../pro_config.dart';
import '../../session/pro_auth_cubit.dart';
import '../agenda/agenda_bloc.dart';
import '../agenda/agenda_event.dart';
import '../../router/app_router.dart';
import '../agenda/agenda_page.dart';
import '../cabinet_messaging/cabinet_messaging_page.dart';
import '../consultation_clinique/consultation_clinique_bloc.dart';
import '../consultation_clinique/consultation_clinique_page.dart';
import '../devis/devis_page.dart';
import '../ordonnances/ordonnances_bloc.dart';
import '../ordonnances/ordonnances_page.dart';
import '../patients/patients_page.dart';
import '../stock/stock_bloc.dart';
import '../lab_work/lab_work_orders_bloc.dart';
import '../lab_work/lab_work_orders_page.dart';
import '../stock/stock_inventory_bloc.dart';
import '../stock/stock_inventory_page.dart';
import '../stock/stock_page.dart';
import '../waiting_room/waiting_room_bloc.dart';
import '../waiting_room/waiting_room_page.dart';
import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'today_notes_bloc.dart';
import 'today_notes_card.dart';
import 'week_summary_card.dart';

/// Entry point for the authenticated praticien home. Delegates layout to
/// [ProShell] (NavigationRail on desktop, Drawer on mobile) with clinical
/// filtering applied via the live [AuthSession].
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: ProConfig.role,
        ),
    };

    return ProShell(
      config: ProConfig.shellConfig,
      session: session,
      // Synchronise l'onglet sélectionné avec l'URL go_router dans les 2
      // sens : `currentRoute` pilote la sélection depuis `state.uri.path`
      // (navigation directe / reload / retour navigateur), et `onNavigate`
      // pousse l'URL via `context.go` quand l'utilisateur clique une
      // destination dans le rail/drawer (#5691, cf. #4813 pour app_pharmacie).
      currentRoute: GoRouterState.of(context).uri.path,
      onNavigate: (destination) => context.go(destination.route),
      bodyBuilder: (ctx, destination) {
        if (destination.route == ProConfig.dashboardRoute) {
          return BlocProvider(
            create: (_) => GetIt.instance<DashboardBloc>()
              ..add(const DashboardLoadRequested()),
            child: const _DashboardContent(),
          );
        }
        if (destination.route == '/agenda') {
          return BlocProvider(
            create: (_) {
              final now = DateTime.now();
              final weekStart = DateTime(
                now.year,
                now.month,
                now.day - (now.weekday - 1),
              );
              return GetIt.instance<AgendaBloc>()
                ..add(AgendaLoadRequested(weekStart: weekStart));
            },
            child: const AgendaBody(),
          );
        }
        if (destination.route == '/waiting-room') {
          return BlocProvider(
            create: (_) => GetIt.instance<WaitingRoomBloc>(),
            child: const WaitingRoomBody(),
          );
        }
        if (destination.route == '/patients') {
          return const PatientsPage();
        }
        if (destination.route == '/consultation') {
          return BlocProvider(
            create: (_) => GetIt.instance<ConsultationCliniqueBloc>(),
            child: const ConsultationCliniqueBody(),
          );
        }
        if (destination.route == '/ordonnances') {
          return BlocProvider(
            create: (_) => GetIt.instance<OrdonnancesBloc>(),
            child: const OrdonnancesBody(),
          );
        }
        if (destination.route == '/devis') {
          // DevisPage fournit son propre BlocProvider<DevisBloc>.
          return const DevisPage();
        }
        if (destination.route == '/stock') {
          return BlocProvider(
            create: (_) => GetIt.instance<StockBloc>(),
            child: const StockPage(),
          );
        }
        if (destination.route == '/stock-inventory') {
          return BlocProvider(
            create: (_) => GetIt.instance<StockInventoryBloc>(),
            child: const StockInventoryPage(),
          );
        }
        if (destination.route == '/lab-work-orders') {
          return BlocProvider(
            create: (_) => GetIt.instance<LabWorkOrdersBloc>(),
            child: const LabWorkOrdersPage(),
          );
        }
        if (destination.route == '/messages') {
          return const CabinetMessagingPage();
        }
        return Center(
          child: NubiaEmptyState(
            icon: Icons.construction_outlined,
            title: destination.label,
          ),
        );
      },
      trailingActions: [
        IconButton(
          key: const Key('nav_team_messages'),
          tooltip: 'Messagerie interne',
          icon: const Icon(Icons.forum_outlined),
          onPressed: () => context.push(AppRouter.teamMessages),
        ),
        // #4539 : banc de test du framework A2UI, jamais eu sa place dans
        // la nav en production (vocabulaire interne + faux CTA « demo.cta »
        // exposés à un praticien). Réservé aux builds debug.
        if (kDebugMode)
          IconButton(
            tooltip: 'Démo A2UI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/a2ui-demo'),
          ),
      ],
      onSignOut: () => context.read<ProAuthCubit>().signOut(),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        return switch (state) {
          DashboardInitial() ||
          DashboardLoading() =>
            const _DashboardLoadingView(key: Key('dashboard_loading')),
          DashboardError(:final message) => NubiaErrorWidget(
              key: const Key('dashboard_error'),
              message: message,
              onRetry: () => context
                  .read<DashboardBloc>()
                  .add(const DashboardLoadRequested()),
            ),
          DashboardLoaded(:final summary) => _DashboardLoadedView(
              summary: summary,
            ),
        };
      },
    );
  }
}

class _DashboardLoadedView extends StatelessWidget {
  const _DashboardLoadedView({required this.summary});

  final ProDashboardSummary summary;

  // Seuil au-delà duquel la colonne droite (430 px fixe) + la gouttière
  // (16 px) laissent assez de place à gauche pour rester lisible.
  static const _wideBreakpoint = 1100.0;
  static const _rightColumnWidth = 430.0;
  static const _gutter = 16.0;

  @override
  Widget build(BuildContext context) {
    final notesCard = BlocProvider(
      create: (_) => GetIt.instance<TodayNotesBloc>()
        ..add(const TodayNotesLoadRequested()),
      child: const TodayNotesCard(),
    );
    final weekSummaryCard = WeekSummaryCard(summary: summary);

    return SingleChildScrollView(
      key: const Key('dashboard_loaded'),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _DashboardHeader(),
                      const SizedBox(height: 16),
                      _SummaryGrid(summary: summary),
                    ],
                  ),
                ),
                const SizedBox(width: _gutter),
                SizedBox(
                  width: _rightColumnWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      notesCard,
                      const SizedBox(height: 16),
                      weekSummaryCard,
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DashboardHeader(),
              const SizedBox(height: 16),
              _SummaryGrid(summary: summary),
              const SizedBox(height: 24),
              notesCard,
              const SizedBox(height: 16),
              weekSummaryCard,
            ],
          );
        },
      ),
    );
  }
}

/// Bandeau de titre du tableau de bord (hiérarchie `h2` + sous-titre `caption`).
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ma journée',
          style: textTheme.headlineSmall?.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          'Aperçu de votre activité clinique du jour',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Squelette de chargement : quatre tuiles de métrique animées.
class _DashboardLoadingView extends StatelessWidget {
  const _DashboardLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NubiaSkeletonLoader(width: 160, height: 28),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (int i = 0; i < 4; i++)
                const NubiaSkeletonLoader(
                  width: 180,
                  height: 108,
                  borderRadius: 12,
                ),
            ],
          ),
          const SizedBox(height: 24),
          const NubiaSkeletonLoader(height: 180, borderRadius: 12),
        ],
      ),
    );
  }
}

/// Grille responsive de [MetricTile] alimentée par [ProDashboardSummary].
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    // #3374 : chaque carte est un raccourci vers l'écran correspondant.
    // « Confirmations en attente » n'a pas d'écran dédié → l'agenda (où se
    // font les confirmations).
    final metrics = <({
      Key key,
      String label,
      String value,
      IconData icon,
      MetricTileVariant variant,
      String route,
    })>[
      (
        key: const Key('metric_appointments'),
        label: 'RDV aujourd\'hui',
        value: '${summary.todayAppointments}',
        icon: Icons.calendar_today_outlined,
        variant: MetricTileVariant.neutral,
        route: AppRouter.agenda,
      ),
      (
        key: const Key('metric_waiting_room'),
        label: 'Salle d\'attente',
        value: '${summary.waitingRoomCount}',
        icon: Icons.event_seat_outlined,
        variant: MetricTileVariant.neutral,
        route: AppRouter.waitingRoom,
      ),
      (
        key: const Key('metric_messages'),
        label: 'Messages non lus',
        value: '${summary.unreadMessages}',
        icon: Icons.chat_bubble_outline,
        variant: summary.unreadMessages > 0
            ? MetricTileVariant.warning
            : MetricTileVariant.neutral,
        route: AppRouter.messages,
      ),
      (
        key: const Key('metric_confirmations'),
        label: 'Confirmations en attente',
        value: '${summary.pendingConfirmations}',
        icon: Icons.pending_actions_outlined,
        variant: summary.pendingConfirmations > 0
            ? MetricTileVariant.warning
            : MetricTileVariant.neutral,
        route: AppRouter.agenda,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        // Vise ~200 px par tuile, borné entre 1 et 4 colonnes.
        final columns =
            (constraints.maxWidth / 200).floor().clamp(1, metrics.length);
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final m in metrics)
              SizedBox(
                width: tileWidth,
                child: MetricTile(
                  key: m.key,
                  icon: m.icon,
                  value: m.value,
                  label: m.label,
                  variant: m.variant,
                  onTap: () => context.go(m.route),
                ),
              ),
          ],
        );
      },
    );
  }
}
