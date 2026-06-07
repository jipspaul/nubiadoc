import 'package:flutter/material.dart';

import '../vault_document.dart';

/// Carte d'un document du coffre-fort.
///
/// Affiche le nom, le badge catégorie et la date. Le bouton « Télécharger »
/// appelle [onDownload] (mock : SnackBar).
class VaultDocumentCard extends StatelessWidget {
  const VaultDocumentCard({
    super.key,
    required this.document,
    required this.onDownload,
  });

  final VaultDocument document;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.name,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _CategoryBadge(category: document.category),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(document.date),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('download_${document.id}'),
              icon: const Icon(Icons.download_outlined),
              color: colorScheme.primary,
              tooltip: 'Télécharger',
              onPressed: onDownload,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}

// ---------------------------------------------------------------------------

/// Badge de catégorie de document.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final VaultCategory category;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        vaultCategoryLabel(category),
        style: textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
