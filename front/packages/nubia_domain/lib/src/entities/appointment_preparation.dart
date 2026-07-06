class PreparationItem {
  final String label;
  final bool required;

  const PreparationItem({required this.label, required this.required});
}

class AppointmentPreparation {
  final String? address;
  final List<PreparationItem> items;

  const AppointmentPreparation({this.address, required this.items});
}
