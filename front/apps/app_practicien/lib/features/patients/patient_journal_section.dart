import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Timeline chronologique unique du dossier patient (#4971 — maquette
/// design-v2 « un journal, pas cinq sections »). Rendu uniquement : agrège
/// via [ListPatientJournalUseCase] (#4970), pas de barre de filtres (ticket
/// dédié).
class PatientJournalSection extends StatefulWidget {
  const PatientJournalSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientJournalSection> createState() => _PatientJournalSectionState();
}

class _PatientJournalSectionState extends State<PatientJournalSection> {
  List<PatientJournalEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await GetIt.instance<ListPatientJournalUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _entries = null;
      }),
      (entries) => setState(() {
        _entries = entries;
        _error = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final entries = _entries;

    return NubiaCard(
      key: const Key('patient_journal_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('Journal du patient', style: textTheme.titleMedium),
              const Spacer(),
              const NubiaBadge.label(label: "tout l'historique"),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: TextStyle(color: cs.error))
          else if (entries == null)
            const Column(
              key: Key('patient_journal_skeleton'),
              children: [
                NubiaSkeletonLoader(height: 56, borderRadius: 8),
                SizedBox(height: 12),
                NubiaSkeletonLoader(height: 56, borderRadius: 8),
                SizedBox(height: 12),
                NubiaSkeletonLoader(height: 56, borderRadius: 8),
              ],
            )
          else if (entries.isEmpty)
            Text(
              'Aucun événement dans le journal pour le moment.',
              key: const Key('patient_journal_empty'),
              style:
                  textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Column(
              key: const Key('patient_journal_entries'),
              children: [
                for (var i = 0; i < entries.length; i++)
                  _JournalEntryRow(
                    key: ValueKey('patient_journal_entry_$i'),
                    entry: entries[i],
                    isLast: i == entries.length - 1,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

const _kJournalMonths = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Une entrée `.je` de la timeline : colonne date + rail coloré par type +
/// corps (titre, code CCAM le cas échéant, sous-titre, tags, montant).
class _JournalEntryRow extends StatelessWidget {
  const _JournalEntryRow({super.key, required this.entry, required this.isLast});

  final PatientJournalEntry entry;
  final bool isLast;

  String get _dayMonth => '${entry.date.day} ${_kJournalMonths[entry.date.month - 1]}';

  String get _yearOrToday {
    final now = DateTime.now();
    final isToday = now.year == entry.date.year &&
        now.month == entry.date.month &&
        now.day == entry.date.day;
    return isToday ? 'aujourd\'hui' : '${entry.date.year}';
  }

  Color _dotColor(NubiaTokens tokens) {
    switch (entry.kind) {
      case PatientJournalKind.acte:
        return NubiaColors.brand600;
      case PatientJournalKind.document:
        return tokens.infoFg;
      case PatientJournalKind.ordonnance:
        return tokens.warningFg;
      case PatientJournalKind.devis:
        return tokens.dangerFg;
      case PatientJournalKind.rendezVous:
        return tokens.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final isActe = entry.kind == PatientJournalKind.acte;
    final ccamCode = isActe ? entry.subtitle : null;
    final subtitleText = isActe ? null : entry.subtitle;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayMonth,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _yearOrToday,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: _dotColor(tokens),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      color: tokens.borderSubtle,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (ccamCode != null) ...[
                        const SizedBox(width: 8),
                        _CcamCodePill(code: ccamCode),
                      ],
                    ],
                  ),
                  if (subtitleText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (entry.tags.isNotEmpty || entry.amountCents != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (entry.tags.isNotEmpty)
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final tag in entry.tags)
                                  _JournalTag(
                                    label: tag,
                                    emphasized: tag.startsWith('Dent '),
                                  ),
                              ],
                            ),
                          )
                        else
                          const Spacer(),
                        if (entry.amountCents != null)
                          Text(
                            formatQuoteCents(entry.amountCents!),
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Code CCAM en pastille monospace (même style que
/// `consultation_clinique/widgets/act_tile.dart` — cohérence inter-écrans).
class _CcamCodePill extends StatelessWidget {
  const _CcamCodePill({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Tag `.mt` : émeraude pour la dent, gris neutre pour le reste (praticien,
/// nombre de lignes, destinataire…).
class _JournalTag extends StatelessWidget {
  const _JournalTag({required this.label, required this.emphasized});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final Color bg = emphasized ? NubiaColors.brand50 : NubiaColors.n100;
    final Color fg = emphasized ? NubiaColors.brand800 : tokens.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
      ),
    );
  }
}
