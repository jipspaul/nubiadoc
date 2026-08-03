import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Colonne « Contexte clinique » de la vue fauteuil (maquette
/// `bo-praticien-core.jsx`) : slot module (ex. tuile « Dent traitée » du
/// module dentaire), antécédents, dernière note datée.
class ClinicalContextPanel extends StatelessWidget {
  const ClinicalContextPanel(
      {super.key, required this.session, this.moduleTile});

  final ClinicalSession session;

  /// Tuile de spécialité insérée en tête du panneau (module dentaire :
  /// « Dent traitée »).
  final Widget? moduleTile;

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final history = session.medicalHistory?.trim();
    final lastNote = session.lastNote;

    return NubiaCard(
      child: Column(
        key: const Key('clinical_context_panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contexte clinique', style: textTheme.titleSmall),
          const SizedBox(height: 12),
          if (moduleTile != null) ...[
            moduleTile!,
            const SizedBox(height: 12),
          ],
          Text(
            'ANTÉCÉDENTS',
            style: textTheme.labelSmall?.copyWith(
              color: muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (history == null || history.isEmpty)
                ? 'Aucun antécédent renseigné.'
                : history,
            key: const Key('clinical_context_history'),
            style: textTheme.bodySmall?.copyWith(
              color: (history == null || history.isEmpty) ? muted : null,
            ),
          ),
          if (lastNote != null && lastNote.excerpt.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              lastNote.date == null
                  ? 'DERNIÈRE NOTE'
                  : 'DERNIÈRE NOTE · ${_formatDate(lastNote.date!)}',
              style: textTheme.labelSmall?.copyWith(
                color: muted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              lastNote.excerpt,
              key: const Key('clinical_context_last_note'),
              style: textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
