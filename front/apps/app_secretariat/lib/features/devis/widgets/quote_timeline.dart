import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Bloc « Suivi » du volet détail devis (#5090) : timeline chronologique
/// répondant à « où en est ce devis ? ».
///
/// `CabinetQuote` ne porte pas (encore) d'horodatage « envoyé au patient »
/// ni « consulté par le patient » (pas de timeline d'événements côté
/// domaine/API) : ces étapes sont omises plutôt que d'afficher un
/// horodatage inventé (cf. issue #5090, note 6). Seules les étapes dont la
/// donnée existe sont rendues, à la lettre de la maquette : « Devis créé »
/// (toujours) et « Signature attendue » (devis envoyé, en attente de
/// signature, avec `expiresAt`) — la maquette ne définit pas d'étape pour
/// un devis déjà signé/payé/expiré, donc aucune n'est inventée ici.
class QuoteTimeline extends StatelessWidget {
  const QuoteTimeline({super.key, required this.quote, this.now});

  final CabinetQuote quote;

  /// Référence pour le décompte de `_formatExpiry` — surchargée par les
  /// tests pour un rendu déterministe, `DateTime.now()` sinon.
  final DateTime? now;

  List<_TimelineStep> _steps() {
    final steps = <_TimelineStep>[
      _TimelineStep(
        id: 'created',
        label: 'Devis créé',
        subtitle: _formatDateTime(quote.createdAt),
        done: true,
      ),
    ];

    final expiresAt = quote.expiresAt;
    if (quote.status == CabinetQuoteStatus.sent && expiresAt != null) {
      steps.add(
        _TimelineStep(
          id: 'pending_signature',
          label: 'Signature attendue',
          subtitle: _formatExpiry(expiresAt, now ?? DateTime.now()),
          done: false,
        ),
      );
    }

    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    if (steps.isEmpty) return const SizedBox.shrink();

    return NubiaCard(
      key: const Key('quote_timeline'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suivi', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          for (final (index, step) in steps.indexed)
            _QuoteTimelineStepTile(
              key: Key('quote_timeline_step_${step.id}'),
              label: step.label,
              subtitle: step.subtitle,
              done: step.done,
              isLast: index == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.done,
  });

  final String id;
  final String label;
  final String subtitle;
  final bool done;
}

/// « JJ/MM · HH:mm » (fuseau local), format imposé par la maquette
/// (ex. « 04/08 · 09:12 »).
String _formatDateTime(DateTime d) {
  final local = d.toLocal();
  final date = '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
  final time = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}

/// « expire le JJ/MM · dans N jours » (maquette) — sans décompte si le
/// délai est déjà écoulé ou expire aujourd'hui.
String _formatExpiry(DateTime expiresAt, DateTime now) {
  final local = expiresAt.toLocal();
  final date = '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
  final days = DateTime(local.year, local.month, local.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days <= 0) return 'expire le $date';
  final unit = days == 1 ? 'jour' : 'jours';
  return 'expire le $date · dans $days $unit';
}

class _QuoteTimelineStepTile extends StatelessWidget {
  const _QuoteTimelineStepTile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.done,
    required this.isLast,
  });

  final String label;
  final String subtitle;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              _QuoteTimelineDot(done: done),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? NubiaColors.brand600 : NubiaColors.n300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: done ? null : NubiaColors.n500,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: NubiaColors.n500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille de l'étape — émeraude pleine (`--brand600`) + coche si réalisée,
/// anneau gris (`--n300`) désactivé sinon (maquette design-v2, #5090).
class _QuoteTimelineDot extends StatelessWidget {
  const _QuoteTimelineDot({required this.done});

  final bool done;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: NubiaColors.brand600,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, size: 12, color: Colors.white),
      );
    }
    return Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: NubiaColors.n300, width: 2),
        ),
      ),
    );
  }
}
