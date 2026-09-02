class PreparationItem {
  final String label;
  final bool required;

  const PreparationItem({required this.label, required this.required});
}

/// Accès physique au cabinet (`establishment.access` côté API) — code de
/// porte, parking, accessibilité PMR.
class PreparationAccess {
  final String? doorCode;
  final bool parking;
  final bool pmr;

  const PreparationAccess({
    this.doorCode,
    required this.parking,
    required this.pmr,
  });
}

class AppointmentPreparation {
  final String? address;
  final String? providerName;
  final PreparationAccess? access;
  final DateTime? reminderAt;
  final List<PreparationItem> items;

  const AppointmentPreparation({
    this.address,
    this.providerName,
    this.access,
    this.reminderAt,
    required this.items,
  });
}
