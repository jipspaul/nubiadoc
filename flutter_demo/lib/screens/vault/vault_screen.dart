import 'package:flutter/material.dart';

import 'vault_document.dart';
import 'widgets/vault_document_card.dart';

/// Coffre-fort documents patient (US-3.5.1).
///
/// Affiche une row de [FilterChip] par catégorie et une [ListView] de
/// [VaultDocumentCard]. Les données sont mockées ([kVaultMockDocuments]).
/// Le filtre de catégorie est un état UI local — aucun Bloc requis ici.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  VaultCategory? _selected;

  static const List<VaultCategory?> _categories = [
    null,
    VaultCategory.quote,
    VaultCategory.invoice,
    VaultCategory.prescription,
    VaultCategory.xray,
    VaultCategory.cbct,
    VaultCategory.photo,
    VaultCategory.report,
    VaultCategory.instructions,
  ];

  List<VaultDocument> get _filtered => _selected == null
      ? kVaultMockDocuments
      : kVaultMockDocuments
          .where((d) => d.category == _selected)
          .toList(growable: false);

  void _onDownload(BuildContext context, VaultDocument doc) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Téléchargement simulé')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes documents')),
      body: Column(
        children: [
          _VaultFilterRow(
            categories: _categories,
            selected: _selected,
            onSelected: (cat) => setState(() => _selected = cat),
          ),
          Expanded(
            child: _VaultDocumentList(
              documents: _filtered,
              onDownload: (doc) => _onDownload(context, doc),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _VaultFilterRow extends StatelessWidget {
  const _VaultFilterRow({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<VaultCategory?> categories;
  final VaultCategory? selected;
  final ValueChanged<VaultCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      key: const Key('vault_filter_row'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: categories.map((cat) {
          final isSelected = selected == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(vaultCategoryLabel(cat)),
              selected: isSelected,
              selectedColor: colorScheme.primaryContainer,
              onSelected: (_) => onSelected(cat),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _VaultDocumentList extends StatelessWidget {
  const _VaultDocumentList({
    required this.documents,
    required this.onDownload,
  });

  final List<VaultDocument> documents;
  final ValueChanged<VaultDocument> onDownload;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Center(
        child: Text(
          'Aucun document',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ListView.builder(
      key: const Key('vault_document_list'),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        return VaultDocumentCard(
          document: doc,
          onDownload: () => onDownload(doc),
        );
      },
    );
  }
}
