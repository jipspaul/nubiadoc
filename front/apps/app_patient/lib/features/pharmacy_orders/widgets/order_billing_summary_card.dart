import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Récap montants (total, part AMO, part mutuelle, reste à régler) — même
/// vocabulaire et même formatage (`formatQuoteCents`) que le devis et
/// l'écran de délivrance pharmacien (#4888/#4063). N'apparaît que si le back
/// a renseigné la ventilation ([PharmacyOrder.hasBillingSummary]).
class OrderBillingSummaryCard extends StatelessWidget {
  const OrderBillingSummaryCard({super.key, required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return NubiaCard(
      key: const Key('order_billing_summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AmountRow(
            label: 'Montant total',
            amountCents: order.billingTotalCents!,
          ),
          const SizedBox(height: 8),
          _AmountRow(
            label: 'Part Assurance Maladie (AMO)',
            amountCents: -order.billingAmoShareCents!,
            valueColor: cs.primary,
          ),
          const SizedBox(height: 8),
          _AmountRow(
            label: 'Part mutuelle (AMC)',
            amountCents: -order.billingAmcShareCents!,
            valueColor: cs.primary,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'À régler au comptoir',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: cs.onSurface),
                ),
              ),
              Text(
                formatQuoteCents(order.billingPatientShareCents!,
                    alwaysShowDecimals: true),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ligne « libellé — montant » du bloc facturation.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amountCents,
    this.valueColor,
  });

  final String label;
  final int amountCents;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Text(
          formatQuoteCents(amountCents),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor ?? cs.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}
