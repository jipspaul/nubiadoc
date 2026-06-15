import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';

/// Per-app configuration that differentiates the two professional apps while
/// they share the same core/domain/data stack.
class ProConfig {
  const ProConfig._();

  static const String appTitle = 'Nubia · Praticien';
  static const String spaceLabel = 'Espace praticien';

  /// Practitioners see clinical content.
  static const ProRole role = ProRole.practitioner;

  /// Wire the clinical + prescription stacks in DI.
  static const bool includeClinical = true;

  /// Side-nav destinations. Practitioners get the clinical "Consultation" entry.
  static const List<({String label, IconData icon, bool clinical})> nav = [
    (label: 'Agenda', icon: Icons.calendar_month_outlined, clinical: false),
    (label: 'Patients', icon: Icons.groups_outlined, clinical: false),
    (label: 'Consultation', icon: Icons.medical_services_outlined, clinical: true),
    (label: 'Messages', icon: Icons.chat_bubble_outline, clinical: false),
  ];
}
