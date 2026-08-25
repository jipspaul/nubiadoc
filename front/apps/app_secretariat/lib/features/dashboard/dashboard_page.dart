import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';

import '../../pro_config.dart';
import '../../session/pro_auth_cubit.dart';
import '../admin_membres/members_access_cubit.dart';
import '../audit_log/audit_log_access_cubit.dart';
import 'cash_collection_cubit.dart';
import 'dashboard_bloc.dart';
import 'dashboard_content.dart';
import 'dashboard_event.dart';
import 'expiring_quotes_summary_cubit.dart';
import 'patient_messages_summary_cubit.dart';
import 'rail_badges_cubit.dart';
import 'waiting_room_summary_cubit.dart';
import 'widgets/global_search_dialog.dart';

/// Shell scaffold shared by every route of the `StatefulShellRoute` declared
/// in `app_router.dart` — wraps [navigationShell] in [ProShell] so the
/// navigation rail/drawer persists across ALL destinations (`/patients`,
/// `/devis`, …), not just `/`. Décision « surface de navigation unique »
/// (#5154) : voir `front/apps/app_secretariat/README.md`.
///
/// [navigationShell] already resolves the active destination's content —
/// [ProShell] is given it as `body`, so it only owns the rail/drawer here
/// (no per-destination `bodyBuilder`, no risk of `bodyBuilder`/`pro_config`
/// order drifting apart).
class SecretariatShell extends StatelessWidget {
  const SecretariatShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

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
    final config = ProConfig.shellConfigFor(
      canManageMembers: canManageMembers,
      canViewAuditLog: canViewAuditLog,
      waitingRoomCount: badges.waitingRoomCount,
      waitingListCount: badges.waitingListCount,
      expiringQuotesCount: badges.expiringQuotesCount,
      unreadMessagesCount: badges.unreadMessagesCount,
    );
    // `ProConfig.shellConfig` (non filtré) est la liste de référence des
    // branches du `StatefulShellRoute` — même ordre, déclaré une seule fois
    // (`app_router.dart`) — donc `navigationShell.currentIndex` s'y résout
    // toujours, indépendamment du filtrage admin/audit appliqué à `config`.
    final currentRoute =
        ProConfig.shellConfig.destinations[navigationShell.currentIndex].route;
    return ProShell(
      config: config,
      session: session,
      // Synchronise l'onglet sélectionné avec l'URL go_router dans les 2
      // sens : `currentRoute` pilote la sélection depuis la branche active
      // (navigation directe / reload / retour navigateur, #4813/#5692), et
      // `onNavigate` bascule de branche quand l'utilisateur clique une
      // destination dans le rail/drawer.
      currentRoute: currentRoute,
      onNavigate: (destination) {
        final index = ProConfig.shellConfig.destinations
            .indexWhere((d) => d.route == destination.route);
        navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        );
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContextBanner(label: session.contextLabel),
          Expanded(child: navigationShell),
        ],
      ),
      trailingActions: [
        // Playground A2UI : artefact de dev, jamais visible en production.
        if (kDebugMode)
          IconButton(
            tooltip: 'Démo A2UI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/a2ui-demo'),
          ),
      ],
      // #5143/#5389 — point d'entrée de recherche globale (destinations de
      // nav + patient/devis/commande) dans la barre de titre, déclenché au
      // clic ou par ⌘K.
      searchHint: 'Patient, devis, commande…',
      onSearchTap: () => openGlobalSearchDialog(
        context,
        destinations: config.destinations,
      ),
      onSignOut: () => context.read<ProAuthCubit>().signOut(),
    );
  }
}

/// Contenu de la branche « Tableau de bord » (`ProConfig.dashboardRoute`) du
/// `StatefulShellRoute` — construit ses propres BLoC/Cubit de synthèse,
/// indépendamment de [SecretariatShell] qui l'héberge.
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key});

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
    return BlocProvider(
      create: (_) => DashboardBloc(
        getAgenda: GetIt.instance<GetCabinetAgendaUseCase>(),
        listWaitingList: GetIt.instance<ListWaitingListUseCase>(),
        listBookableSlots: GetIt.instance<ListBookableSlotsUseCase>(),
      )..add(const DashboardLoadRequested()),
      child: BlocProvider<CashCollectionCubit>(
        create: (_) => GetIt.instance<CashCollectionCubit>()..load(),
        child: BlocProvider<WaitingRoomSummaryCubit>(
          create: (_) => GetIt.instance<WaitingRoomSummaryCubit>()..load(),
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
