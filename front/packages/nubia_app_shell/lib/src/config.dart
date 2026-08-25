import 'package:flutter/material.dart';

/// Couleur sémantique d'un badge compteur de navigation (#5142) : verte pour
/// une charge « personnes présentes / non lus », ambre pour une charge
/// « à traiter avant échéance ». Résolue en [Color] par [ProShell], qui a
/// accès aux [NubiaTokens] du thème courant.
enum ProNavBadgeColor { brand, warning }

/// A destination entry in the [ProShell] side navigation.
///
/// [requiresClinical] gates the entry behind [AuthSession.canAccessClinical]:
/// secretaries and other non-clinical roles never see clinical destinations.
class ProNavDestination {
  const ProNavDestination({
    required this.label,
    required this.icon,
    required this.route,
    this.requiresClinical = false,
    this.badgeCount,
    this.badgeColor = ProNavBadgeColor.brand,
    this.group,
  });

  final String label;
  final IconData icon;

  /// GoRouter route path — used for deep-linking when a [StatefulShellRoute]
  /// is wired up. Stored now; navigation via [context.go] is a future step.
  final String route;
  final bool requiresClinical;

  /// Compteur affiché en badge sur l'icône de la destination (rail desktop
  /// ET drawer mobile). `null` ou `0` : aucun badge — rétro-compatible avec
  /// les apps qui ne le fournissent pas encore (#5387).
  final int? badgeCount;

  /// Couleur sémantique du badge (#5142) — ignorée si [badgeCount] est
  /// `null`/`0`. Par défaut [ProNavBadgeColor.brand].
  final ProNavBadgeColor badgeColor;

  /// En-tête de groupe (#5139) sous lequel cette destination est nichée dans
  /// le rail/drawer, ex. « Réglages du cabinet ». `null` (défaut) : aucun
  /// groupe, la destination s'affiche directement — comportement inchangé
  /// pour les apps qui ne groupent pas encore leurs entrées. Les
  /// destinations partageant le même [group] doivent être contiguës dans
  /// [ProConfig.destinations] : elles forment une seule section, sous un
  /// unique en-tête repliable.
  final String? group;
}

/// Configuration passed from each professional app to [ProShell].
class ProConfig {
  const ProConfig({
    required this.appTitle,
    required this.spaceLabel,
    required this.destinations,
    this.collapsedGroups = const {},
  });

  final String appTitle;
  final String spaceLabel;
  final List<ProNavDestination> destinations;

  /// Noms de [ProNavDestination.group] repliés par défaut (#5139), ex.
  /// « Réglages du cabinet » — un paramétrage ouvert quelques fois par an,
  /// masqué derrière son en-tête jusqu'au clic. Vide par défaut : aucun
  /// groupe replié, comportement inchangé pour les apps sans groupes.
  final Set<String> collapsedGroups;
}
