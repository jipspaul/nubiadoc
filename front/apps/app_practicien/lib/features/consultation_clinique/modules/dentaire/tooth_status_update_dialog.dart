import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../../dental_chart/dental_chart_page.dart'
    show kToothStatuses, kToothStatusLabels;

/// Dialogue de PROPOSITION de mise à jour d'odontogramme après un acte
/// portant une dent (périmètre non-dispositif-médical, docs/06 §E4.8) :
/// le statut est pré-sélectionné d'après l'acte (`tooth_act_suggestions`)
/// mais RIEN n'est écrit sans validation explicite — « Ignorer » ne fait
/// aucune écriture. Retourne le statut choisi, ou `null` si ignoré.
class ToothStatusUpdateDialog extends StatefulWidget {
  const ToothStatusUpdateDialog({
    super.key,
    required this.tooth,
    required this.actLabel,
    required this.suggestedStatus,
  });

  final String tooth;
  final String actLabel;
  final String suggestedStatus;

  /// Ouvre le dialogue ; résout avec le statut validé ou `null` (ignoré).
  static Future<String?> show(
    BuildContext context, {
    required String tooth,
    required String actLabel,
    required String suggestedStatus,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => ToothStatusUpdateDialog(
          tooth: tooth,
          actLabel: actLabel,
          suggestedStatus: suggestedStatus,
        ),
      );

  @override
  State<ToothStatusUpdateDialog> createState() =>
      _ToothStatusUpdateDialogState();
}

class _ToothStatusUpdateDialogState extends State<ToothStatusUpdateDialog> {
  late String _status = widget.suggestedStatus;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('tooth_status_update_dialog'),
      title: Text('Mettre à jour l\'état de la dent ${widget.tooth} ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suite à l\'acte « ${widget.actLabel} ». Le schéma dentaire '
            'n\'est modifié que si vous validez.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final status in kToothStatuses)
                NubiaChip(
                  key: Key('tooth_status_choice_$status'),
                  label: kToothStatusLabels[status] ?? status,
                  selected: status == _status,
                  onTap: () => setState(() => _status = status),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('tooth_status_update_ignore'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ignorer'),
        ),
        NubiaButton(
          key: const Key('tooth_status_update_confirm'),
          size: NubiaButtonSize.sm,
          icon: Icons.check,
          label: 'Mettre à jour',
          onPressed: () => Navigator.of(context).pop(_status),
        ),
      ],
    );
  }
}
