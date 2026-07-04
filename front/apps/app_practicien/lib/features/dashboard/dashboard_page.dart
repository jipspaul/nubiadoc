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
import '../agenda/agenda_page.dart';
import '../cabinet_messaging/cabinet_messaging_page.dart';
import '../consultation_clinique/consultation_clinique_bloc.dart';
import '../consultation_clinique/consultation_clinique_page.dart';
import '../ordonnances/ordonnances_bloc.dart';
import '../ordonnances/ordonnances_page.dart';
import '../patients/patients_page.dart';
import '../waiting_room/waiting_room_bloc.dart';
import '../waiting_room/waiting_room_page.dart';
import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'today_notes_bloc.dart';
import 'today_notes_card.dart';

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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('dashboard_loaded'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DashboardHeader(),
          const SizedBox(height: 16),
          _SummaryGrid(summary: summary),
          const SizedBox(height: 24),
          BlocProvider(
            create: (_) => GetIt.instance<TodayNotesBloc>()
              ..add(const TodayNotesLoadRequested()),
            child: const TodayNotesCard(),
          ),
        ],
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
    final metrics = <({
      Key key,
      String label,
      String value,
      IconData icon,
      MetricTileVariant variant,
    })>[
      (
        key: const Key('metric_appointments'),
        label: 'RDV aujourd\'hui',
        value: '${summary.todayAppointments}',
        icon: Icons.calendar_today_outlined,
        variant: MetricTileVariant.neutral,
      ),
      (
        key: const Key('metric_waiting_room'),
        label: 'Salle d\'attente',
        value: '${summary.waitingRoomCount}',
        icon: Icons.event_seat_outlined,
        variant: MetricTileVariant.neutral,
      ),
      (
        key: const Key('metric_messages'),
        label: 'Messages non lus',
        value: '${summary.unreadMessages}',
        icon: Icons.chat_bubble_outline,
        variant: summary.unreadMessages > 0
            ? MetricTileVariant.warning
            : MetricTileVariant.neutral,
      ),
      (
        key: const Key('metric_confirmations'),
        label: 'Confirmations en attente',
        value: '${summary.pendingConfirmations}',
        icon: Icons.pending_actions_outlined,
        variant: summary.pendingConfirmations > 0
            ? MetricTileVariant.warning
            : MetricTileVariant.neutral,
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
                ),
              ),
          ],
        );
      },
    );
  }
}
