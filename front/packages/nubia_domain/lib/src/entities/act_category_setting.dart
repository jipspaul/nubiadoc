import 'package:equatable/equatable.dart';

/// Réglage d'une catégorie d'actes CCAM pour le cabinet (#7185/#7186) —
/// `enabled: false` masque la catégorie du catalogue exposé au praticien
/// (`GET /v1/ccam/acts`) et de la consultation clinique.
class ActCategorySetting extends Equatable {
  final String category;
  final bool enabled;

  const ActCategorySetting({required this.category, required this.enabled});

  ActCategorySetting copyWith({bool? enabled}) => ActCategorySetting(
        category: category,
        enabled: enabled ?? this.enabled,
      );

  @override
  List<Object?> get props => [category, enabled];
}
