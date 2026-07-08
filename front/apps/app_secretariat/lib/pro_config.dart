import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;

/// App-level constants for the secrétariat app (administrative-only).
///
/// No [requiresClinical] destination is declared — the structural guarantee
/// that secretaries never see clinical surfaces.
class ProConfig {
  const ProConfig._();

  static const String appTitle = 'Nubia · Secrétariat';
  static const String spaceLabel = 'Espace secrétariat';

  static const ProRole role = ProRole.secretary;
  static const bool includeClinical = false;

  static const String dashboardRoute = '/';

  /// Route de l'entrée « Membres » — administration réservée aux
  /// secrétaires-admin. Masquée pour un secrétaire simple (403 sur
  /// `GET /v1/cabinet/members`, cf. #3468) via [shellConfigFor].
  static const String membersRoute = '/admin-membres';

  static const shell.ProConfig shellConfig = shell.ProConfig(
    appTitle: appTitle,
    spaceLabel: spaceLabel,
    destinations: [
      shell.ProNavDestination(
        label: 'Tableau de bord',
        icon: Icons.dashboard_outlined,
        route: dashboardRoute,
      ),
      shell.ProNavDestination(
        label: 'Salle d\'attente',
        icon: Icons.airline_seat_recline_normal_outlined,
        route: '/salle-attente',
      ),
      shell.ProNavDestination(
        label: 'Liste d\'attente',
        icon: Icons.format_list_bulleted_outlined,
        route: '/liste-attente',
      ),
      shell.ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_month_outlined,
        route: '/agenda',
      ),
      shell.ProNavDestination(
        label: 'Créneaux',
        icon: Icons.event_available_outlined,
        route: '/bookable-slots',
      ),
      shell.ProNavDestination(
        label: 'Patients',
        icon: Icons.groups_outlined,
        route: '/patients',
      ),
      shell.ProNavDestination(
        label: 'Devis',
        icon: Icons.receipt_long_outlined,
        route: '/devis',
      ),
      shell.ProNavDestination(
        label: 'Messages',
        icon: Icons.chat_bubble_outline,
        route: '/messages',
      ),
      shell.ProNavDestination(
        label: 'Membres',
        icon: Icons.group_outlined,
        route: membersRoute,
      ),
      shell.ProNavDestination(
        label: 'Secrétariats',
        icon: Icons.business_outlined,
        route: '/admin-secretariats',
      ),
    ],
  );

  /// Config de navigation filtrée selon l'accès admin aux membres.
  ///
  /// L'entrée « Membres » n'est conservée que lorsque [canManageMembers] est
  /// vrai (secrétaire-admin). Pour un secrétaire simple,
  /// `GET /v1/cabinet/members` renvoie 403 : l'onglet serait une impasse
  /// (#3468). Les autres destinations gardent leur ordre relatif — on retire
  /// l'entrée de la liste plutôt que de la neutraliser, donc pas de trou
  /// d'index côté [shell.ProShell].
  static shell.ProConfig shellConfigFor({required bool canManageMembers}) {
    if (canManageMembers) return shellConfig;
    return shell.ProConfig(
      appTitle: appTitle,
      spaceLabel: spaceLabel,
      destinations: shellConfig.destinations
          .where((d) => d.route != membersRoute)
          .toList(),
    );
  }
}
