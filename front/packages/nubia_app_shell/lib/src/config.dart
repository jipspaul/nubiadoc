import 'package:flutter/material.dart';

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
  });

  final String label;
  final IconData icon;

  /// GoRouter route path — used for deep-linking when a [StatefulShellRoute]
  /// is wired up. Stored now; navigation via [context.go] is a future step.
  final String route;
  final bool requiresClinical;
}

/// Configuration passed from each professional app to [ProShell].
class ProConfig {
  const ProConfig({
    required this.appTitle,
    required this.spaceLabel,
    required this.destinations,
  });

  final String appTitle;
  final String spaceLabel;
  final List<ProNavDestination> destinations;
}
