import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;

/// App-level constants for the praticien app.
///
/// [role] is still used by [ProAuthCubit] to seed a stub [AuthSession] until
/// `GET /v1/me` is wired. [shellConfig] is passed to [ProShell].
class ProConfig {
  const ProConfig._();

  static const String appTitle = 'Nubia · Praticien';
  static const String spaceLabel = 'Espace praticien';

  static const ProRole role = ProRole.practitioner;
  static const bool includeClinical = true;

  static const String dashboardRoute = '/';

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
        label: 'Agenda',
        icon: Icons.calendar_month_outlined,
        route: '/agenda',
      ),
      shell.ProNavDestination(
        label: 'Salle d\'attente',
        icon: Icons.event_seat_outlined,
        route: '/waiting-room',
        requiresClinical: true,
      ),
      shell.ProNavDestination(
        label: 'Patients',
        icon: Icons.groups_outlined,
        route: '/patients',
      ),
      shell.ProNavDestination(
        label: 'Consultation',
        icon: Icons.medical_services_outlined,
        route: '/consultation',
        requiresClinical: true,
      ),
      shell.ProNavDestination(
        label: 'Ordonnances',
        icon: Icons.medication_outlined,
        route: '/ordonnances',
        requiresClinical: true,
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
        label: 'Messages',
        icon: Icons.chat_bubble_outline,
        route: '/messages',
      ),
    ],
  );
}
