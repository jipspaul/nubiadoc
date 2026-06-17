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

  static const shell.ProConfig shellConfig = shell.ProConfig(
    appTitle: appTitle,
    spaceLabel: spaceLabel,
    destinations: [
      shell.ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_month_outlined,
        route: '/agenda',
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
    ],
  );
}
