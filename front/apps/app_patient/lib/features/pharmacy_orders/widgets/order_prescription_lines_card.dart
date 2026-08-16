import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte « Votre ordonnance » — liste les lignes de l'ordonnance (nom,
/// quantité, posologie) sous la timeline de suivi (design-v2, #5349).
/// Ne s'affiche que si le back a renseigné [PharmacyOrder.lines] (même
/// entité [PrescriptionItem] que côté pharmacien) — pas de valeurs codées
/// en dur.
class OrderPrescriptionLinesCard extends StatelessWidget {
  const OrderPrescriptionLinesCard({super.key, required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = order.lines;
    final counterLabel =
        lines.length == 1 ? '1 ligne' : '${lines.length} lignes';

    return Column(
      key: const Key('order_prescription_lines_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child:
                  Text('Votre ordonnance', style: theme.textTheme.titleLarge),
            ),
            Text(
              counterLabel,
              key: const Key('order_prescription_lines_count'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: NubiaColors.n500, fontSize: 11.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        NubiaCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: NubiaColors.n100),
                _PrescriptionLineRow(item: lines[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PrescriptionLineRow extends StatelessWidget {
  const _PrescriptionLineRow({required this.item});

  final PrescriptionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final detail = item.duration.isEmpty
        ? item.posology
        : '${item.posology}, ${item.duration}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.medication, color: NubiaColors.brand700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${item.quantity} · $detail',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: NubiaColors.n500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.check_circle, color: tokens.successFg),
        ],
      ),
    );
  }
}
