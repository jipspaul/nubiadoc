import 'package:flutter/material.dart';

import '../models/financial_summary.dart';

/// Section liste de documents (devis ou factures).
class DocumentListSection extends StatelessWidget {
  const DocumentListSection({
    super.key,
    required this.title,
    required this.documents,
  });

  final String title;
  final List<FinancialDocument> documents;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.titleLarge),
            const SizedBox(height: 8),
            ...documents.map((doc) => _DocumentRow(document: doc)),
          ],
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document});

  final FinancialDocument document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isPaid = document.status == DocumentStatus.paid;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isPaid ? Icons.receipt_long : Icons.receipt_outlined,
            size: 20,
            color: isPaid ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(document.label, style: textTheme.bodyMedium),
          ),
          Text(
            '${(document.amountCents / 100).toStringAsFixed(2)} €',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
