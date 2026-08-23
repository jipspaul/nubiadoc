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
import '../audit_log/audit_log_access_cubit.dart';
import '../audit_log/audit_log_bloc.dart';
import '../audit_log/audit_log_event.dart';
import '../audit_log/audit_log_page.dart';
import '../bookable_slots/bookable_slots_bloc.dart';
import '../bookable_slots/bookable_slots_page.dart';
import '../cabinet_stats/cabinet_stats_bloc.dart';
import '../cabinet_stats/cabinet_stats_event.dart';
import '../cabinet_stats/cabinet_stats_page.dart';
import '../cabinet_payouts/cabinet_payouts_bloc.dart';
import '../cabinet_payouts/cabinet_payouts_event.dart';
import '../cabinet_payouts/cabinet_payouts_page.dart';
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
import 'cash_collection_cubit.dart';
import 'dashboard_bloc.dart';
import 'dashboard_content.dart';
import 'dashboard_event.dart';
import 'expiring_quotes_summary_cubit.dart';
import 'patient_messages_summary_cubit.dart';
import 'rail_badges_cubit.dart';
import 'waiting_room_summary_cubit.dart';
import 'widgets/global_search_dialog.dart';

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

    // Sonde l'accès admin aux membres et au journal d'accès dès l'ouverture :
    // l'app fixe le rôle `secretary`, seul le 403 sur leurs endpoints
    // respectifs distingue le secrétaire-admin/manager du secrétaire simple
    // (#3468, #4155). Les entrées de nav correspondantes sont masquées dès
    // que le 403 confirme le rôle insuffisant. Le même signal
    // (`canManageMembers`) gate aussi « Secrétariats », dont le listing n'est
    // pas admin-only mais dont la gestion l'est (#5156).
    return BlocProvider<MembersAccessCubit>(
      create: (_) => GetIt.instance<MembersAccessCubit>()..probe(),
      child: BlocProvider<AuditLogAccessCubit>(
        create: (_) => GetIt.instance<AuditLogAccessCubit>()..probe(),
        child: BlocProvider<RailBadgesCubit>(
          create: (_) => GetIt.instance<RailBadgesCubit>()..load(),
          child: Builder(
            builder: (context) => _buildShell(context, session),
          ),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context, AuthSession session) {
    final canManageMembers =
        context.watch<MembersAccessCubit>().canManageMembers;
    final canViewAuditLog =
        context.watch<AuditLogAccessCubit>().canViewAuditLog;
    final badges = context.watch<RailBadgesCubit>().state;
    return ProShell(
      config: ProConfig.shellConfigFor(
        canManageMembers: canManageMembers,
        canViewAuditLog: canViewAuditLog,
        waitingRoomCount: badges.waitingRoomCount,
        waitingListCount: badges.waitingListCount,
        expiringQuotesCount: badges.expiringQuotesCount,
        unreadMessagesCount: badges.unreadMessagesCount,
      ),
      session: session,
      // Synchronise l'onglet sélectionné avec l'URL go_router dans les 2
      // sens : `currentRoute` pilote la sélection depuis `state.uri.path`
      // (navigation directe / reload / retour navigateur, #4813/#5692), et
      // `onNavigate` pousse l'URL via `context.go` quand l'utilisateur
      // clique une destination dans le rail/drawer.
      currentRoute: GoRouterState.of(context).uri.path,
      onNavigate: (destination) => context.go(destination.route),
      bodyBuilder: (ctx, destination) {
        final builder = _dashboardBodyBuilders(session)[destination.route];
        final body = builder != null
            ? builder(ctx)
            : Center(
                child: NubiaEmptyState(
                  icon: Icons.construction_outlined,
                  title: destination.label,
                ),
              );
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
      // #5389 — point d'entrée de recherche globale (patient/devis/commande)
      // dans la barre de titre, déclenché au clic ou par ⌘K.
      searchHint: 'Patient, devis, commande…',
      onSearchTap: () => openGlobalSearchDialog(context),
      onSignOut: () => context.read<ProAuthCubit>().signOut(),
    );
  }
}

/// Table des corps d'écran par route, indexée sur [NavDestination.route] —
/// remplace la chaîne `if/else if` historique du `bodyBuilder` (#5372).
/// Fallback (route absente de la table) : [NubiaEmptyState] dans le
/// `bodyBuilder` ci-dessus.
Map<String, WidgetBuilder> _dashboardBodyBuilders(AuthSession session) {
  return {
    ProConfig.dashboardRoute: (_) => BlocProvider(
          create: (_) => DashboardBloc(
            getAgenda: GetIt.instance<GetCabinetAgendaUseCase>(),
            listWaitingList: GetIt.instance<ListWaitingListUseCase>(),
            listBookableSlots: GetIt.instance<ListBookableSlotsUseCase>(),
          )..add(const DashboardLoadRequested()),
          child: BlocProvider<CashCollectionCubit>(
            create: (_) => GetIt.instance<CashCollectionCubit>()..load(),
            child: BlocProvider<WaitingRoomSummaryCubit>(
              create: (_) =>
                  GetIt.instance<WaitingRoomSummaryCubit>()..load(),
              child: BlocProvider<PatientMessagesSummaryCubit>(
                create: (_) =>
                    GetIt.instance<PatientMessagesSummaryCubit>()..load(),
                child: BlocProvider<ExpiringQuotesSummaryCubit>(
                  create: (_) =>
                      GetIt.instance<ExpiringQuotesSummaryCubit>()..load(),
                  child: DashboardContent(session: session),
                ),
              ),
            ),
          ),
        ),
    '/salle-attente': (_) => BlocProvider(
          create: (_) => GetIt.instance<WaitingRoomBloc>(),
          child: const WaitingRoomBody(),
        ),
    '/agenda': (_) => const AgendaPage(),
    '/admin-secretariats': (_) => BlocProvider(
          create: (_) => GetIt.instance<AdminSecretiariatsBloc>(),
          child: const AdminSecretiariatsBody(),
        ),
    '/bookable-slots': (_) => BlocProvider(
          create: (_) => GetIt.instance<BookableSlotsBloc>(),
          child: const BookableSlotsBody(),
        ),
    '/liste-attente': (_) => BlocProvider(
          create: (_) => GetIt.instance<WaitingListBloc>(),
          child: const WaitingListPage(),
        ),
    '/patients': (_) => BlocProvider(
          create: (_) => GetIt.instance<PatientsBloc>(),
          child: const PatientsPage(),
        ),
    '/devis': (_) => BlocProvider(
          create: (_) => GetIt.instance<DevisBloc>(),
          child: const DevisPage(),
        ),
    '/stock': (_) => BlocProvider(
          create: (_) => GetIt.instance<StockBloc>(),
          child: const StockPage(),
        ),
    '/messages': (_) => BlocProvider(
          create: (_) => GetIt.instance<CabinetMessagingBloc>()
            ..add(const CabinetMessagingConversationsLoadRequested()),
          child: const CabinetMessagingPage(),
        ),
    '/admin-membres': (_) => BlocProvider(
          create: (_) => GetIt.instance<AdminMembresBloc>(),
          child: const AdminMembresPage(),
        ),
    '/appointment-motifs': (_) => BlocProvider(
          create: (_) => GetIt.instance<AppointmentMotifsBloc>(),
          child: const AppointmentMotifsPage(),
        ),
    '/cabinet-stats': (_) => BlocProvider(
          create: (_) => GetIt.instance<CabinetStatsBloc>()
            ..add(const CabinetStatsLoadRequested()),
          child: const CabinetStatsBody(),
        ),
    '/cabinet-payouts': (_) => BlocProvider(
          create: (_) => GetIt.instance<CabinetPayoutsBloc>()
            ..add(const CabinetPayoutsLoadRequested()),
          child: const CabinetPayoutsBody(),
        ),
    ProConfig.auditLogRoute: (_) => BlocProvider(
          create: (_) => GetIt.instance<AuditLogBloc>()
            ..add(const AuditLogLoadRequested()),
          child: const AuditLogBody(),
        ),
  };
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
