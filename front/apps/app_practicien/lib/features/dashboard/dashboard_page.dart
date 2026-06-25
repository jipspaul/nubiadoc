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
        if (destination.route == '/waiting-room') {
          return BlocProvider(
            create: (_) => GetIt.instance<WaitingRoomBloc>(),
            child: const WaitingRoomBody(),
          );
        }
        return const Center(
          child: NubiaEmptyState(
            icon: Icons.construction_outlined,
            title: 'Bientôt disponible',
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
          DashboardInitial() || DashboardLoading() => const _DashboardSkeleton(
              key: Key('dashboard_loading'),
            ),
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

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: List.generate(
          4,
          (_) => const SizedBox(
            width: 160,
            child: NubiaSkeletonLoader(height: 96),
          ),
        ),
      ),
    );
  }
}

class _DashboardLoadedView extends StatelessWidget {
  const _DashboardLoadedView({required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryGrid(summary: summary),
          const SizedBox(height: 16),
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

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        label: 'RDV aujourd\'hui',
        value: '${summary.todayAppointments}',
        icon: Icons.calendar_today_outlined,
      ),
      (
        label: 'Salle d\'attente',
        value: '${summary.waitingRoomCount}',
        icon: Icons.event_seat_outlined,
      ),
      (
        label: 'Messages non lus',
        value: '${summary.unreadMessages}',
        icon: Icons.chat_bubble_outline,
      ),
      (
        label: 'Confirmations en attente',
        value: '${summary.pendingConfirmations}',
        icon: Icons.pending_actions_outlined,
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final card in cards)
          SizedBox(
            width: 160,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(card.icon, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      card.value,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
