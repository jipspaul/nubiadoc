import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../pro_config.dart';
import '../../router/app_router.dart';
import '../../session/pro_auth_cubit.dart';
import '../admin_membres/admin_membres_bloc.dart';
import '../admin_membres/admin_membres_page.dart';
import '../admin_membres/members_access_cubit.dart';
import '../admin_secretariats/admin_secretariats_bloc.dart';
import '../admin_secretariats/admin_secretariats_page.dart';
import '../appointment_motifs/appointment_motifs_bloc.dart';
import '../appointment_motifs/appointment_motifs_page.dart';
import '../agenda/agenda_page.dart';
import '../bookable_slots/bookable_slots_bloc.dart';
import '../bookable_slots/bookable_slots_page.dart';
import '../cabinet_stats/cabinet_stats_bloc.dart';
import '../cabinet_stats/cabinet_stats_event.dart';
import '../cabinet_stats/cabinet_stats_page.dart';
import '../cabinet_messaging/cabinet_messaging_bloc.dart';
import '../cabinet_messaging/cabinet_messaging_event.dart';
import '../cabinet_messaging/cabinet_messaging_page.dart';
import '../devis/devis_bloc.dart';
import '../devis/devis_page.dart';
import '../patients/patients_bloc.dart';
import '../patients/patients_page.dart';
import '../stock/stock_bloc.dart';
import '../stock/stock_page.dart';
import '../waiting_list/waiting_list_bloc.dart';
import '../waiting_list/waiting_list_page.dart';
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

    // Sonde l'accès admin aux membres dès l'ouverture : l'app fixe le rôle
    // `secretary`, seul le 403 sur `GET /v1/cabinet/members` distingue le
    // secrétaire-admin du secrétaire simple (#3468). L'entrée de nav « Membres »
    // est masquée dès que ce 403 confirme le non-admin.
    return BlocProvider<MembersAccessCubit>(
      create: (_) => GetIt.instance<MembersAccessCubit>()..probe(),
      child: Builder(
        builder: (context) => _buildShell(context, session),
      ),
    );
  }

  Widget _buildShell(BuildContext context, AuthSession session) {
    final canManageMembers =
        context.watch<MembersAccessCubit>().canManageMembers;
    return ProShell(
      config: ProConfig.shellConfigFor(canManageMembers: canManageMembers),
      session: session,
      bodyBuilder: (ctx, destination) {
        final Widget body;
        if (destination.route == ProConfig.dashboardRoute) {
          body = BlocProvider(
            create: (_) => DashboardBloc(
              getAgenda: GetIt.instance<GetCabinetAgendaUseCase>(),
              listWaitingList: GetIt.instance<ListWaitingListUseCase>(),
            )..add(const DashboardLoadRequested()),
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
        } else if (destination.route == '/liste-attente') {
          body = BlocProvider(
            create: (_) => GetIt.instance<WaitingListBloc>(),
            child: const WaitingListPage(),
          );
        } else if (destination.route == '/patients') {
          body = BlocProvider(
            create: (_) => GetIt.instance<PatientsBloc>(),
            child: const PatientsPage(),
          );
        } else if (destination.route == '/devis') {
          body = BlocProvider(
            create: (_) => GetIt.instance<DevisBloc>(),
            child: const DevisPage(),
          );
        } else if (destination.route == '/stock') {
          body = BlocProvider(
            create: (_) => GetIt.instance<StockBloc>(),
            child: const StockPage(),
          );
        } else if (destination.route == '/messages') {
          body = BlocProvider(
            create: (_) => GetIt.instance<CabinetMessagingBloc>()
              ..add(const CabinetMessagingConversationsLoadRequested()),
            child: const CabinetMessagingPage(),
          );
        } else if (destination.route == '/admin-membres') {
          body = BlocProvider(
            create: (_) => GetIt.instance<AdminMembresBloc>(),
            child: const AdminMembresPage(),
          );
        } else if (destination.route == '/appointment-motifs') {
          body = BlocProvider(
            create: (_) => GetIt.instance<AppointmentMotifsBloc>(),
            child: const AppointmentMotifsPage(),
          );
        } else if (destination.route == '/cabinet-stats') {
          body = BlocProvider(
            create: (_) => GetIt.instance<CabinetStatsBloc>()
              ..add(const CabinetStatsLoadRequested()),
            child: const CabinetStatsBody(),
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
          key: const Key('nav_team_messages'),
          tooltip: 'Messagerie interne',
          icon: const Icon(Icons.forum_outlined),
          onPressed: () => context.push(AppRouter.teamMessages),
        ),
        // Playground A2UI : artefact de dev, jamais visible en production.
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
            const _DashboardSkeleton(),
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
            _DashboardLoadedView(
              todayCount: todayCount,
              pendingCount: pendingCount,
              waitingCount: waitingCount,
            ),
        };
      },
    );
  }
}

/// Largeur maximale du contenu centré (poste de travail desktop).
const double _kContentMaxWidth = 1120;

/// Vue chargée du tableau de bord opérationnel : en-tête + tuiles de flux du
/// jour ([MetricTile]) + cartes récapitulatives. Purement administratif —
/// aucune donnée clinique n'est affichée (cloisonnement secrétariat).
class _DashboardLoadedView extends StatelessWidget {
  const _DashboardLoadedView({
    required this.todayCount,
    required this.pendingCount,
    required this.waitingCount,
  });

  final int todayCount;
  final int pendingCount;
  final int waitingCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final metrics = <Widget>[
      MetricTile(
        key: const Key('stat_rdv_today'),
        icon: Icons.calendar_today_outlined,
        value: '$todayCount',
        label: "RDV aujourd'hui",
      ),
      MetricTile(
        key: const Key('stat_pending'),
        icon: Icons.pending_actions_outlined,
        value: '$pendingCount',
        label: 'RDV à confirmer',
        variant: MetricTileVariant.warning,
      ),
      MetricTile(
        key: const Key('stat_waiting_list'),
        icon: Icons.format_list_bulleted_outlined,
        value: '$waitingCount',
        label: "Liste d'attente",
      ),
    ];

    return SingleChildScrollView(
      key: const Key('dashboard_loaded'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tableau de bord',
                style: textTheme.headlineSmall?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                'Flux du jour — activité administrative du cabinet',
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                key: const Key('dashboard_stats_row'),
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final tile in metrics) SizedBox(width: 220, child: tile),
                ],
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 720;
                  final cards = [
                    _DashboardPanel(
                      icon: Icons.event_available_outlined,
                      title: 'Prochains rendez-vous',
                      body: todayCount == 0
                          ? 'Aucun rendez-vous planifié aujourd’hui.'
                          : '$todayCount rendez-vous au programme du jour.',
                      hint: 'Consultez l’agenda du cabinet pour le détail.',
                    ),
                    _DashboardPanel(
                      icon: Icons.pending_actions_outlined,
                      title: 'À traiter',
                      body: pendingCount == 0
                          ? 'Aucune demande en attente de confirmation.'
                          : '$pendingCount demande(s) à confirmer.',
                      hint: waitingCount == 0
                          ? 'Liste d’attente vide.'
                          : '$waitingCount patient(s) en liste d’attente.',
                    ),
                  ];
                  if (!twoColumns) {
                    return Column(
                      children: [
                        for (final c in cards) ...[
                          c,
                          if (c != cards.last) const SizedBox(height: 16),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[1]),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte récapitulative du tableau de bord (titre + texte + indice).
class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String body;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return NubiaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Skeleton de chargement du tableau de bord (tuiles + cartes).
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('dashboard_loading'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              NubiaSkeletonLoader(width: 220, height: 28),
              SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 220,
                    child: NubiaSkeletonLoader(height: 118, borderRadius: 12),
                  ),
                  SizedBox(
                    width: 220,
                    child: NubiaSkeletonLoader(height: 118, borderRadius: 12),
                  ),
                  SizedBox(
                    width: 220,
                    child: NubiaSkeletonLoader(height: 118, borderRadius: 12),
                  ),
                ],
              ),
              SizedBox(height: 28),
              NubiaSkeletonLoader(height: 120, borderRadius: 12),
            ],
          ),
        ),
      ),
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
