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

  /// Groupe « Réglages du cabinet » (#5139, maquette design-v2) — paramétrage
  /// ouvert quelques fois par an, replié par défaut derrière son chevron pour
  /// que les écrans quotidiens restent en haut du rail/drawer.
  static const String settingsGroup = 'Réglages du cabinet';

  /// Les 5 groupes nommés de la colonne de navigation (#5137, maquette
  /// design-v2 « Architecture de navigation ») — chaque destination
  /// appartient à exactement un de ces groupes, dans cet ordre.
  static const String todayGroup = 'Ma journée';
  static const String patientsGroup = 'Patients';
  static const String billingGroup = 'Facturation';
  static const String messagesGroup = 'Messages';

  static const shell.ProConfig shellConfig = shell.ProConfig(
    appTitle: appTitle,
    spaceLabel: spaceLabel,
    collapsedGroups: {settingsGroup},
    destinations: [
      // Groupe « Ma journée » (maquette design-v2, #5141) — synthèse du jour,
      // pas un doublon de l'Agenda — voir la décision #5155 documentée sur
      // [dashboardRoute].
      shell.ProNavDestination(
        label: 'Tableau de bord',
        icon: Icons.space_dashboard,
        route: dashboardRoute,
        group: todayGroup,
      ),
      // Outil complet de gestion des RDV sur la semaine (filtre praticien,
      // création, confirmation) — voir la décision #5155 sur [dashboardRoute].
      shell.ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_month,
        route: '/agenda',
        group: todayGroup,
      ),
      shell.ProNavDestination(
        label: 'Salle d\'attente',
        icon: Icons.meeting_room,
        route: '/salle-attente',
        group: todayGroup,
      ),
      shell.ProNavDestination(
        label: 'Demandes de créneau',
        icon: Icons.hourglass_top,
        route: '/liste-attente',
        group: todayGroup,
      ),
      // Groupe « Patients ».
      shell.ProNavDestination(
        label: 'Fiches patients',
        icon: Icons.groups,
        route: '/patients',
        group: patientsGroup,
      ),
      // Action du quotidien (verbe à l'infinitif, pas une rubrique) — groupe
      // « Patients » de la maquette design-v2, cf. #5150.
      shell.ProNavDestination(
        label: 'Prendre un RDV',
        icon: Icons.event_available,
        route: appointmentsRoute,
        group: patientsGroup,
      ),
      // Groupe « Facturation ».
      shell.ProNavDestination(
        label: 'Devis',
        icon: Icons.description,
        route: '/devis',
        group: billingGroup,
      ),
      shell.ProNavDestination(
        label: 'Encaissements',
        icon: Icons.payments,
        route: '/cabinet-payouts',
        group: billingGroup,
      ),
      // Groupe « Messages ».
      shell.ProNavDestination(
        label: 'Patients',
        icon: Icons.chat_bubble,
        route: '/messages',
        group: messagesGroup,
      ),
      // Messagerie interne au cabinet — anciennement icône trailing isolée,
      // désormais voisine de « Messages » sous le même groupe (#5151) : deux
      // messageries distinctes, enfin lisibles côte à côte.
      shell.ProNavDestination(
        label: 'Équipe',
        icon: Icons.forum,
        route: '/team-messages',
        group: messagesGroup,
      ),
      // Groupe « Réglages du cabinet » (repliable, replié par défaut — #5139).
      shell.ProNavDestination(
        label: 'Statistiques',
        icon: Icons.bar_chart,
        route: '/cabinet-stats',
        group: settingsGroup,
      ),
      shell.ProNavDestination(
        label: 'Créneaux ouverts',
        icon: Icons.event_available_outlined,
        route: '/bookable-slots',
        group: settingsGroup,
      ),
      shell.ProNavDestination(
        label: 'Motifs de RDV',
        icon: Icons.event_note_outlined,
        route: '/appointment-motifs',
        group: settingsGroup,
      ),
      shell.ProNavDestination(
        label: 'Stock',
        icon: Icons.inventory_2,
        route: '/stock',
        group: settingsGroup,
      ),
      shell.ProNavDestination(
        label: 'Membres',
        icon: Icons.group_outlined,
        route: membersRoute,
        group: settingsGroup,
      ),
      shell.ProNavDestination(
        label: 'Secrétariats',
        icon: Icons.business,
        route: secretariatsRoute,
        group: settingsGroup,
      ),
      shell.ProNavDestination(
        label: "Journal d'audit",
        icon: Icons.history,
        route: auditLogRoute,
        group: settingsGroup,
      ),
    ],
  );

  /// Couleur de badge par route (#5142, maquette « Architecture de
  /// navigation ») : vert (`--brand600`) pour une charge « présents / non
  /// lus », ambre (`--warnFg`) pour une charge « à traiter » (demandes de
  /// créneau, devis en attente de signature).
  static const Map<String, shell.ProNavBadgeColor> _badgeColors = {
    '/salle-attente': shell.ProNavBadgeColor.brand,
    '/liste-attente': shell.ProNavBadgeColor.warning,
    '/devis': shell.ProNavBadgeColor.warning,
    '/messages': shell.ProNavBadgeColor.brand,
  };

  /// Config de navigation filtrée selon l'accès admin aux membres/secrétariats
  /// et au journal d'accès, badges compteurs injectés sur les destinations
  /// correspondantes (#5388 : salle d'attente, demandes de créneau, devis
  /// expirants, messages non lus ; #5142 : couleurs vert/ambre conformes à
  /// la maquette).
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
  /// trou d'index côté [shell.ProShell] ; si le groupe entier est retiré, son
  /// en-tête disparaît aussi — [shell.ProShell] n'affiche jamais l'en-tête
  /// d'un groupe vide (#5139).
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
      collapsedGroups: const {settingsGroup},
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
          badgeColor: _badgeColors[d.route] ?? d.badgeColor,
          group: d.group,
        );
      }).toList(),
    );
  }
}
