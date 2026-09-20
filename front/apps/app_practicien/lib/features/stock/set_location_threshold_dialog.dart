import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Résultat renvoyé par [SetLocationThresholdDialog] à la validation —
/// `null` si le dialog est annulé, distinct de `threshold: null` (seuil
/// effacé).
typedef SetLocationThresholdResult = ({int? threshold});

/// Formulaire de réglage du seuil d'alerte d'un article pour une salle
/// donnée (#7182/#7183).
Future<SetLocationThresholdResult?> showSetLocationThresholdDialog(
  BuildContext context, {
  required String itemLabel,
  required String locationName,
  required int? currentThreshold,
}) {
  return showDialog<SetLocationThresholdResult>(
    context: context,
    builder: (_) => SetLocationThresholdDialog(
      itemLabel: itemLabel,
      locationName: locationName,
      currentThreshold: currentThreshold,
    ),
  );
}

class SetLocationThresholdDialog extends StatefulWidget {
  const SetLocationThresholdDialog({
    super.key,
    required this.itemLabel,
    required this.locationName,
    required this.currentThreshold,
  });

  final String itemLabel;
  final String locationName;
  final int? currentThreshold;

  @override
  State<SetLocationThresholdDialog> createState() =>
      _SetLocationThresholdDialogState();
}

class _SetLocationThresholdDialogState
    extends State<SetLocationThresholdDialog> {
  late final _thresholdController = TextEditingController(
    text: widget.currentThreshold?.toString() ?? '',
  );

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Seuil d\'alerte — ${widget.itemLabel}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Salle : ${widget.locationName}'),
            const SizedBox(height: 12),
            NubiaTextField(
              key: const Key('location_threshold_field'),
              controller: _thresholdController,
              label: 'Seuil (vide = aucune alerte)',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_location_threshold_button'),
          onPressed: () {
            final raw = _thresholdController.text.trim();
            final threshold = raw.isEmpty ? null : int.tryParse(raw);
            if (raw.isNotEmpty && threshold == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saisissez un nombre valide.')),
              );
              return;
            }
            Navigator.of(context).pop((threshold: threshold));
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
