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

  /// Route du « Tableau de bord » (`DashboardPage`).
  ///
  /// #5155 — analyse du recoupement avec [AgendaPage] (`/agenda`), tranchée :
  /// les deux entrées sont conservées, rôles distincts.
  /// - Tableau de bord (`DashboardContent`) : synthèse opérationnelle de
  ///   *la journée en cours uniquement*, lecture seule (`TodayFlowCard`), plus
  ///   la charge du cabinet (salle d'attente, demandes de créneau, caisse,
  ///   occupation de la semaine, praticiens présents). Aucune action de
  ///   RDV (pas de création/confirmation) ; `TodayFlowCard` renvoie
  ///   explicitement vers `/agenda` (« Ouvrir l'agenda »).
  /// - Agenda (`AgendaPage`) : outil opérationnel complet sur *la semaine*,
  ///   avec filtre par praticien, créneaux disponibles et actions de
  ///   gestion des RDV (création, confirmation).
  /// Aucune fusion/suppression : le dashboard n'expose qu'un extrait de la
  /// journée (pas de duplication de la grille semaine ni des actions de
  /// l'agenda), conformément à son rôle de synthèse.
  static const String dashboardRoute = '/';

  /// Route de l'entrée « Prendre un RDV » (`AppointmentsPage`) — action du
  /// quotidien, groupe « Patients » de la maquette design-v2 (#5150).
  static const String appointmentsRoute = '/appointments';

  /// Route de l'entrée « Membres » — administration réservée aux
  /// secrétaires-admin. Masquée pour un secrétaire simple (403 sur
  /// `GET /v1/cabinet/members`, cf. #3468) via [shellConfigFor].
  static const String membersRoute = '/admin-membres';

  /// Route du « Journal d'accès » — réservé admin/manager côté back
  /// (`ProAdminOrManagerClaims`). Masquée pour un rôle insuffisant (403 sur
  /// `GET /v1/cabinet/audit-log`, #4155) via [shellConfigFor].
  static const String auditLogRoute = '/audit-log';

  /// Route de l'entrée « Secrétariats ». `GET /v1/cabinet/secretariats`
  /// (listing) est ouvert à tout membre pro (`ProMemberClaims`), mais sa
  /// création/administration (`POST`/`PATCH`/`DELETE /v1/cabinet/secretariats`)
  /// exige `ProAdminClaims` — le même rôle strict `admin` que
  /// `GET /v1/cabinet/members` (#3468). On ne peut donc pas sonder le listing
  /// lui-même (il ne renverra jamais 403) ; on réutilise le signal déjà
  /// confirmé de [membersRoute] pour masquer cette entrée admin (#5156).
  static const String secretariatsRoute = '/admin-secretariats';

  static const shell.ProConfig shellConfig = shell.ProConfig(
    appTitle: appTitle,
    spaceLabel: spaceLabel,
    destinations: [
      // Synthèse du jour, pas un doublon de l'Agenda — voir la décision
      // #5155 documentée sur [dashboardRoute].
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
        label: 'Demandes de créneau',
        icon: Icons.format_list_bulleted_outlined,
        route: '/liste-attente',
      ),
      // Outil complet de gestion des RDV sur la semaine (filtre praticien,
      // création, confirmation) — voir la décision #5155 sur [dashboardRoute].
      shell.ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_month_outlined,
        route: '/agenda',
      ),
      shell.ProNavDestination(
        label: 'Créneaux ouverts',
        icon: Icons.event_available_outlined,
        route: '/bookable-slots',
      ),
      shell.ProNavDestination(
        label: 'Fiches patients',
        icon: Icons.groups_outlined,
        route: '/patients',
      ),
      // Action du quotidien (verbe à l'infinitif, pas une rubrique) — groupe
      // « Patients » de la maquette design-v2, cf. #5150.
      shell.ProNavDestination(
        label: 'Prendre un RDV',
        icon: Icons.event_available,
        route: appointmentsRoute,
      ),
      shell.ProNavDestination(
        label: 'Devis',
        icon: Icons.receipt_long_outlined,
        route: '/devis',
      ),
      shell.ProNavDestination(
        label: 'Stock',
        icon: Icons.inventory_2_outlined,
        route: '/stock',
      ),
      shell.ProNavDestination(
        label: 'Patients',
        icon: Icons.chat_bubble_outline,
        route: '/messages',
      ),
      // Messagerie interne au cabinet — anciennement icône trailing isolée,
      // désormais voisine de « Messages » sous le même groupe (#5151) : deux
      // messageries distinctes, enfin lisibles côte à côte.
      shell.ProNavDestination(
        label: 'Équipe',
        icon: Icons.forum_outlined,
        route: '/team-messages',
      ),
      shell.ProNavDestination(
        label: 'Motifs de RDV',
        icon: Icons.event_note_outlined,
        route: '/appointment-motifs',
      ),
      shell.ProNavDestination(
        label: 'Membres',
        icon: Icons.group_outlined,
        route: membersRoute,
      ),
      shell.ProNavDestination(
        label: 'Secrétariats',
        icon: Icons.business_outlined,
        route: secretariatsRoute,
      ),
      shell.ProNavDestination(
        label: 'Statistiques',
        icon: Icons.bar_chart_outlined,
        route: '/cabinet-stats',
      ),
      shell.ProNavDestination(
        label: 'Encaissements',
        icon: Icons.payments_outlined,
        route: '/cabinet-payouts',
      ),
      shell.ProNavDestination(
        label: "Journal d'audit",
        icon: Icons.history_outlined,
        route: auditLogRoute,
      ),
    ],
  );

  /// Config de navigation filtrée selon l'accès admin aux membres/secrétariats
  /// et au journal d'accès, badges compteurs injectés sur les destinations
  /// correspondantes (#5388 : salle d'attente, demandes de créneau, devis
  /// expirants, messages non lus).
  ///
  /// Les entrées « Membres »/« Secrétariats »/« Journal d'accès » — le groupe
  /// « Réglages du cabinet » de la maquette design-v2 — ne sont conservées que
  /// lorsque l'accès correspondant est confirmé (#5156). [canManageMembers]
  /// gate à la fois [membersRoute] et [secretariatsRoute] : les deux exigent
  /// le rôle strict `admin` côté back (`ProAdminClaims`), et seul
  /// `GET /v1/cabinet/members` renvoie 403 pour le sonder (`GET
  /// /v1/cabinet/secretariats` est ouvert à tout membre, #3468). Le journal
  /// d'accès reste gaté séparément (`ProAdminOrManagerClaims`, admin ou
  /// manager, #4155). Les autres destinations gardent leur ordre relatif — on
  /// retire l'entrée de la liste plutôt que de la neutraliser, donc pas de
  /// trou d'index côté [shell.ProShell] ; si le groupe entier est retiré,
  /// aucun en-tête ne reste (la nav n'a pas d'en-têtes de groupe).
  static shell.ProConfig shellConfigFor({
    required bool canManageMembers,
    required bool canViewAuditLog,
    int waitingRoomCount = 0,
    int waitingListCount = 0,
    int expiringQuotesCount = 0,
    int unreadMessagesCount = 0,
  }) {
    final badgeCounts = <String, int>{
      '/salle-attente': waitingRoomCount,
      '/liste-attente': waitingListCount,
      '/devis': expiringQuotesCount,
      '/messages': unreadMessagesCount,
    };
    return shell.ProConfig(
      appTitle: appTitle,
      spaceLabel: spaceLabel,
      destinations: shellConfig.destinations
          .where((d) =>
              (canManageMembers ||
                  (d.route != membersRoute && d.route != secretariatsRoute)) &&
              (canViewAuditLog || d.route != auditLogRoute))
          .map((d) {
        final badgeCount = badgeCounts[d.route];
        if (badgeCount == null) return d;
        return shell.ProNavDestination(
          label: d.label,
          icon: d.icon,
          route: d.route,
          requiresClinical: d.requiresClinical,
          badgeCount: badgeCount,
        );
      }).toList(),
    );
  }
}
