import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';

/// Per-app configuration for the secretariat app. Administrative only — it must
/// never expose clinical content (medical confidentiality / cloisonnement).
class ProConfig {
  const ProConfig._();

  static const String appTitle = 'Nubia · Secrétariat';
  static const String spaceLabel = 'Espace secrétariat';

  /// Secretaries are administrative-only (canAccessClinical == false).
  static const ProRole role = ProRole.secretary;

  /// Clinical + prescription stacks are NEVER registered in this binary.
  static const bool includeClinical = false;

  /// Side-nav destinations — no clinical "Consultation" entry.
  static const List<({String label, IconData icon, bool clinical})> nav = [
    (label: 'Agenda', icon: Icons.calendar_month_outlined, clinical: false),
    (label: 'Patients', icon: Icons.groups_outlined, clinical: false),
    (label: 'Devis', icon: Icons.receipt_long_outlined, clinical: false),
    (label: 'Messages', icon: Icons.chat_bubble_outline, clinical: false),
  ];
}
