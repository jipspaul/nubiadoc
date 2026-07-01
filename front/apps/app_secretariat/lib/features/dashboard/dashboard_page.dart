import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../pro_config.dart';
import '../../session/pro_auth_cubit.dart';
import '../admin_secretariats/admin_secretariats_bloc.dart';
import '../admin_secretariats/admin_secretariats_page.dart';
import '../agenda/agenda_page.dart';
import '../bookable_slots/bookable_slots_bloc.dart';
import '../bookable_slots/bookable_slots_page.dart';
import '../waiting_room/waiting_room_bloc.dart';
import '../waiting_room/waiting_room_page.dart';
import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

/// Entry point for the authenticated secrétariat home. Delegates layout to
/// [ProShell] (NavigationRail on desktop, Drawer on mobile). Clinical
/// filtering is enforced inside [ProShell] via [AuthSession.canAccessClinical];
/// all destinations here are administrative-only so the filter is redundant
/// but provides defense-in-depth.
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
        final Widget body;
        if (destination.route == ProConfig.dashboardRoute) {
          body = BlocProvider(
            create: (_) => DashboardBloc()..add(const DashboardLoadRequested()),
            child: const _DashboardContent(),
          );
        } else if (destination.route == '/salle-attente') {
          body = BlocProvider(
            create: (_) => GetIt.instance<WaitingRoomBloc>(),
            child: const WaitingRoomBody(),
          );
        } else if (destination.route == '/agenda') {
          body = const AgendaPage();
        } else if (destination.route == '/admin-secretariats') {
          body = BlocProvider(
            create: (_) => GetIt.instance<AdminSecretiariatsBloc>(),
            child: const AdminSecretiariatsBody(),
          );
        } else if (destination.route == '/bookable-slots') {
          body = BlocProvider(
            create: (_) => GetIt.instance<BookableSlotsBloc>(),
            child: const BookableSlotsBody(),
          );
        } else {
          body = Center(
            child: NubiaEmptyState(
              icon: Icons.construction_outlined,
              title: destination.label,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ContextBanner(label: session.contextLabel),
            Expanded(child: body),
          ],
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
          DashboardInitial() || DashboardLoading() => const Center(
              child: CircularProgressIndicator(key: Key('dashboard_loading'))),
          DashboardError(:final message) => NubiaErrorWidget(
              key: const Key('dashboard_error'),
              message: message,
              onRetry: () => context
                  .read<DashboardBloc>()
                  .add(const DashboardLoadRequested()),
            ),
          DashboardLoaded(
            :final todayCount,
            :final pendingCount,
            :final waitingCount,
          ) =>
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                key: const Key('dashboard_stats_row'),
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    key: const Key('stat_rdv_today'),
                    icon: Icons.calendar_today_outlined,
                    label: "RDV aujourd'hui",
                    count: todayCount,
                  ),
                  _StatCard(
                    key: const Key('stat_pending'),
                    icon: Icons.pending_actions_outlined,
                    label: 'En attente',
                    count: pendingCount,
                  ),
                  _StatCard(
                    key: const Key('stat_waiting_list'),
                    icon: Icons.format_list_bulleted_outlined,
                    label: 'Liste attente',
                    count: waitingCount,
                  ),
                ],
              ),
            ),
        };
      },
    );
  }
}

/// Coloured banner displaying the current secrétariat/establishment context.
/// Hidden (zero-height) when [label] is null.
class ContextBanner extends StatelessWidget {
  const ContextBanner({super.key, required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) return const SizedBox.shrink();
    return Container(
      key: const Key('context_banner'),
      color: Theme.of(context).colorScheme.primaryContainer,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(label!),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
