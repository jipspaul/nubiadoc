import 'package:equatable/equatable.dart';

import 'prescription.dart';

/// A reusable prescription template (`prescription_template`, #4073/#4074).
/// `isGlobal` : seeded standard template, visible to every cabinet — vs a
/// cabinet's own template.
class PrescriptionTemplate extends Equatable {
  final String id;
  final String label;
  final List<PrescriptionItem> items;
  final bool isGlobal;

  const PrescriptionTemplate({
    required this.id,
    required this.label,
    required this.items,
    required this.isGlobal,
  });

  @override
  List<Object?> get props => [id, label, items, isGlobal];
}
