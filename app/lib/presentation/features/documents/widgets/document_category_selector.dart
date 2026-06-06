import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/document.dart';

/// A dropdown selector for document categories used on the upload screen.
class DocumentCategorySelector extends StatelessWidget {
  const DocumentCategorySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final DocumentCategory selected;
  final ValueChanged<DocumentCategory> onChanged;

  static const List<DocumentCategory> _uploadableCategories = [
    DocumentCategory.prescription,
    DocumentCategory.mutualCard,
    DocumentCategory.consent,
    DocumentCategory.xray,
    DocumentCategory.photo,
    DocumentCategory.other,
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DocumentCategory>(
      key: const Key('category_selector'),
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'Catégorie',
        border: OutlineInputBorder(),
      ),
      items: _uploadableCategories
          .map(
            (cat) => DropdownMenuItem(
              value: cat,
              child: Text(_labelFor(cat)),
            ),
          )
          .toList(),
      onChanged: (cat) {
        if (cat != null) onChanged(cat);
      },
    );
  }

  static String _labelFor(DocumentCategory category) {
    switch (category) {
      case DocumentCategory.prescription:
        return 'Ordonnance';
      case DocumentCategory.mutualCard:
        return 'Carte mutuelle';
      case DocumentCategory.consent:
        return 'Consentement';
      case DocumentCategory.xray:
        return 'Radio';
      case DocumentCategory.photo:
        return 'Photo';
      case DocumentCategory.other:
        return 'Autre';
      default:
        return category.name;
    }
  }
}
