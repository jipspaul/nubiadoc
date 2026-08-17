import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte de refus actionnable (état terminal `rejected`) : explique le
/// refus et propose une suite — renvoyer l'ordonnance (toujours valable) à
/// une autre pharmacie, ou appeler la pharmacie (design-v2, #5351).
class OrderRejectedCard extends StatelessWidget {
  const OrderRejectedCard({super.key, required this.order, this.pharmacyPhone});

  final PharmacyOrder order;

  /// Numéro de la pharmacie DE LA COMMANDE (#5645) — `null` tant qu'il n'est
  /// pas résolu, le bouton « Appeler » est alors désactivé.
  final String? pharmacyPhone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final pharmacyName = order.pharmacyName ?? 'La pharmacie';

    return Container(
      key: const Key('timeline_terminal_banner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.dangerBg,
        border: Border.all(color: NubiaColors.dangerBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error, color: tokens.dangerFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Commande refusée',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.dangerFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$pharmacyName ne peut pas préparer cette ordonnance. Votre '
            "ordonnance reste valable — vous pouvez l'envoyer à une autre "
            'pharmacie.',
            style: theme.textTheme.bodyMedium,
          ),
          if (order.rejectionReason != null) ...[
            const SizedBox(height: 12),
            _RejectionReasonBox(reason: order.rejectionReason!),
          ],
          const SizedBox(height: 12),
          _RejectedTimeline(order: order),
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('choose_other_pharmacy_button'),
            label: 'Choisir une autre pharmacie',
            icon: Icons.swap_horiz,
            variant: NubiaButtonVariant.destructive,
            onPressed: () => context.push(
              '/pharmacy/send?prescriptionId='
              '${Uri.encodeComponent(order.prescriptionId)}',
            ),
          ),
          const SizedBox(height: 8),
          NubiaButton(
            key: const Key('call_pharmacy_button'),
            label: 'Appeler la pharmacie',
            icon: Icons.call,
            variant: NubiaButtonVariant.secondary,
            onPressed: pharmacyPhone == null
                ? null
                : () => callPhoneNumber(pharmacyPhone!),
          ),
        ],
      ),
    );
  }
}

class _RejectionReasonBox extends StatelessWidget {
  const _RejectionReasonBox({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('rejection_reason_box'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Motif indiqué par la pharmacie',
              style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Text('« $reason »',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// Timeline réduite : ordonnance transmise (faite) puis refusée (pastille
/// rouge, horodatée) — les 4 étapes du parcours nominal restent grisées.
class _RejectedTimeline extends StatelessWidget {
  const _RejectedTimeline({required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RejectedTimelineStep(
          key: Key('rejected_timeline_sent'),
          icon: Icons.check_circle,
          done: true,
          label: 'Ordonnance transmise',
        ),
        _RejectedTimelineStep(
          key: const Key('rejected_timeline_rejected'),
          icon: Icons.close,
          done: true,
          isDanger: true,
          label: 'Refusée par la pharmacie',
          subtitle: locale.formatShortDate(order.updatedAt.toLocal()),
        ),
        const _RejectedTimelineStep(
          label: 'Commande reçue',
        ),
        const _RejectedTimelineStep(
          label: 'En cours de préparation',
        ),
        const _RejectedTimelineStep(
          label: 'Prête à être retirée',
        ),
        const _RejectedTimelineStep(
          label: 'Retirée',
          isLast: true,
        ),
      ],
    );
  }
}

class _RejectedTimelineStep extends StatelessWidget {
  const _RejectedTimelineStep({
    super.key,
    required this.label,
    this.icon,
    this.done = false,
    this.isDanger = false,
    this.subtitle,
    this.isLast = false,
  });

  final String label;
  final IconData? icon;
  final bool done;
  final bool isDanger;
  final String? subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final color = isDanger
        ? tokens.dangerFg
        : done
            ? tokens.successFg
            : theme.disabledColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon ?? Icons.radio_button_unchecked,
                  size: 20, color: color),
              if (!isLast) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
