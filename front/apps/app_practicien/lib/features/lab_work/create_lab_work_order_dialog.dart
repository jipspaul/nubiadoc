import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat renvoyé par [CreateLabWorkOrderDialog] à la validation (#8031) —
/// consommé par l'appelant pour dispatcher `LabWorkOrdersCreateRequested`
/// (`POST /v1/cabinet/lab-work-orders`).
typedef CreateLabWorkOrderResult = ({
  String labName,
  int purchasePriceCents,
  DateTime expectedReturnAt,
});

/// Formulaire de création d'un bon de travail (#8031) pour [patient] — labo,
/// prix d'achat et date de retour attendue, mêmes champs que le body de
/// `POST /v1/cabinet/lab-work-orders` (`api/src/lab_work_orders.rs`).
class CreateLabWorkOrderDialog extends StatefulWidget {
  const CreateLabWorkOrderDialog({super.key, required this.patient});

  final CabinetPatient patient;

  @override
  State<CreateLabWorkOrderDialog> createState() =>
      _CreateLabWorkOrderDialogState();
}

class _CreateLabWorkOrderDialogState extends State<CreateLabWorkOrderDialog> {
  final _labNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  DateTime? _expectedReturnAt;

  @override
  void dispose() {
    _labNameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  static String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  /// Même conversion euros -> centimes que `ccam_picker.dart`
  /// (`_eurosToCents`) : virgule ou point décimal acceptés.
  static int? _eurosToCents(String raw) {
    final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final euros = double.tryParse(normalized);
    if (euros == null || euros < 0) return null;
    return (euros * 100).round();
  }

  Future<void> _pickExpectedReturnAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedReturnAt ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _expectedReturnAt = picked);
    }
  }

  void _confirm() {
    final labName = _labNameCtrl.text.trim();
    if (labName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez le nom du laboratoire.')),
      );
      return;
    }
    final purchasePriceCents = _eurosToCents(_priceCtrl.text);
    if (purchasePriceCents == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Indiquez le prix d'achat.")),
      );
      return;
    }
    final expectedReturnAt = _expectedReturnAt;
    if (expectedReturnAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez la date de retour attendue.')),
      );
      return;
    }
    Navigator.of(context).pop((
      labName: labName,
      purchasePriceCents: purchasePriceCents,
      expectedReturnAt: expectedReturnAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('create_lab_work_order_dialog'),
      title: Text('Nouveau bon — ${widget.patient.fullName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('create_lab_work_order_lab_name'),
              controller: _labNameCtrl,
              decoration: const InputDecoration(labelText: 'Laboratoire'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('create_lab_work_order_price'),
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Prix d'achat (€)"),
            ),
            const SizedBox(height: 4),
            ListTile(
              key: const Key('create_lab_work_order_due_date'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(
                _expectedReturnAt == null
                    ? 'Choisir la date'
                    : _formatDate(_expectedReturnAt!),
              ),
              subtitle: const Text('Retour attendu'),
              onTap: _pickExpectedReturnAt,
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
          key: const Key('create_lab_work_order_submit'),
          onPressed: _confirm,
          child: const Text('Créer le bon'),
        ),
      ],
    );
  }
}
