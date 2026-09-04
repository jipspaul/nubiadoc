import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Bloc « Suivi » du volet détail devis d'officine (maquette design-v2,
/// écart #2 de la QA #6454) : « Devis créé » (toujours), « Envoyé au
/// patient » (dès que le devis a quitté l'état brouillon) et « Réponse du
/// patient » (en attente tant que non tranché, sinon la date de décision).
/// Contrairement au devis cabinet (`app_secretariat`), `PharmacyQuote`
/// porte déjà `sentAt`/`decidedAt` : les trois étapes de la maquette sont
/// donc toutes rendues avec de vraies données, sans rien inventer.
class PharmacyQuoteTimeline extends StatelessWidget {
  const PharmacyQuoteTimeline({super.key, required this.quote, this.now});

  final PharmacyQuote quote;

  /// Référence pour le décompte de l'étape « en attente » — surchargée par
  /// les tests pour un rendu déterministe, `DateTime.now()` sinon.
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

    if (quote.status == PharmacyQuoteStatus.draft) return steps;

    final sentAt = quote.sentAt;
    steps.add(
      _TimelineStep(
        id: 'sent',
        label: 'Envoyé au patient',
        subtitle: sentAt != null ? _formatDateTime(sentAt) : '—',
        done: sentAt != null,
      ),
    );

    if (quote.status == PharmacyQuoteStatus.sent) {
      steps.add(
        _TimelineStep(
          id: 'pending',
          label: 'Réponse du patient',
          subtitle:
              'en attente depuis ${_relativeDays(sentAt ?? quote.createdAt, now ?? DateTime.now())}',
          done: false,
        ),
      );
    } else {
      final decidedAt = quote.decidedAt;
      steps.add(
        _TimelineStep(
          id: 'decided',
          label: 'Réponse du patient',
          subtitle: decidedAt != null ? _formatDateTime(decidedAt) : '—',
          done: true,
        ),
      );
    }

    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    return Column(
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

String _formatDateTime(DateTime d) {
  final local = d.toLocal();
  final date = '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
  final time = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}

String _relativeDays(DateTime date, DateTime now) {
  final d = DateTime(date.year, date.month, date.day);
  final n = DateTime(now.year, now.month, now.day);
  final days = n.difference(d).inDays;
  if (days <= 0) return "aujourd'hui";
  if (days == 1) return '1 jour';
  return '$days jours';
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
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: done ? null : NubiaColors.n500,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: NubiaColors.n500,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
