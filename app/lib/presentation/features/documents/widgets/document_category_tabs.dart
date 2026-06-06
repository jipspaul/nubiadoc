import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Horizontal scrollable row of category filter chips for the documents screen.
///
/// [categories] defines the available filters in order. Passing `null` as
/// [selected] means "Tous". Tapping a chip calls [onSelected] with the
/// corresponding [DocumentCategory] (or `null` for "Tous").
class DocumentCategoryTabs extends StatelessWidget {
  const DocumentCategoryTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<DocumentCategory?> categories;
  final DocumentCategory? selected;
  final ValueChanged<DocumentCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((category) {
          final isSelected = selected == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                _labelFor(category),
                style: textTheme.labelMedium?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
              selected: isSelected,
              selectedColor: colorScheme.primary,
              backgroundColor: tokens.primarySubtleBg,
              checkmarkColor: colorScheme.onPrimary,
              side: BorderSide(
                color: isSelected
                    ? colorScheme.primary
                    : tokens.borderDefault,
              ),
              onSelected: (_) => onSelected(category),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _labelFor(DocumentCategory? category) {
    switch (category) {
      case null:
        return 'Tous';
      case DocumentCategory.quote:
        return 'Devis';
      case DocumentCategory.invoice:
        return 'Factures';
      case DocumentCategory.prescription:
        return 'Ordonnances';
      case DocumentCategory.xray:
        return 'Radios';
      case DocumentCategory.cbct:
        return 'CBCT';
      case DocumentCategory.photo:
        return 'Photos';
      case DocumentCategory.report:
        return 'Comptes-rendus';
      case DocumentCategory.consent:
        return 'Consentements';
      case DocumentCategory.instructions:
        return 'Instructions';
      case DocumentCategory.mutualCard:
        return 'Carte mutuelle';
      case DocumentCategory.other:
        return 'Autres';
    }
  }
}
