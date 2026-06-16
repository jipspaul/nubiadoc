import 'package:flutter/material.dart';

/// A single entry in the pro side-navigation.
class ProNavDestination {
  const ProNavDestination({
    required this.icon,
    required this.label,
    required this.route,
    this.requiresClinical = false,
  });

  final IconData icon;
  final String label;
  final String route;

  /// If true, this destination is hidden when the authenticated session
  /// does not have [AuthSession.canAccessClinical].
  final bool requiresClinical;
}

/// Top-level configuration for [ProShell].
class ProConfig {
  const ProConfig({
    required this.nav,
    required this.homeRoute,
  });

  final List<ProNavDestination> nav;
  final String homeRoute;
}
