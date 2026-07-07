import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat renvoyé par [CreateSlotDialog] à la validation.
typedef CreateSlotResult = ({
  String practitionerId,
  DateTime startsAt,
  DateTime endsAt,
});

class CreateSlotDialog extends StatefulWidget {
  const CreateSlotDialog({super.key, required this.practitioners});

  /// Roster des praticiens du cabinet — obligatoire pour rattacher le créneau à
  /// un médecin (le back rejette un `practitioner_id` vide → 422, #3465).
  final List<CabinetPractitioner> practitioners;

  @override
  State<CreateSlotDialog> createState() => _CreateSlotDialogState();
}

class _CreateSlotDialogState extends State<CreateSlotDialog> {
  static DateTime _todayMidnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  CabinetPractitioner? _practitioner;
  DateTime _date = _todayMidnight();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 9, minute: 30);

  @override
  void initState() {
    super.initState();
    // Présélection si le cabinet n'a qu'un praticien.
    if (widget.practitioners.length == 1) {
      _practitioner = widget.practitioners.first;
    }
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasPractitioners = widget.practitioners.isNotEmpty;
    return AlertDialog(
      title: const Text('Créer un créneau'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasPractitioners)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Aucun praticien disponible pour rattacher le créneau.',
                key: Key('create_slot_no_practitioner'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Praticien *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CabinetPractitioner>(
                    key: const Key('practitioner_picker_dropdown'),
                    isExpanded: true,
                    value: _practitioner,
                    hint: const Text('Sélectionner un praticien'),
                    items: widget.practitioners
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.displayName),
                            ))
                        .toList(),
                    onChanged: (p) => setState(() => _practitioner = p),
                  ),
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(_formatDate(_date)),
            subtitle: const Text('Date'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: Text(_startTime.format(context)),
            subtitle: const Text('Heure début'),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _startTime,
              );
              if (picked != null) setState(() => _startTime = picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.access_time_filled),
            title: Text(_endTime.format(context)),
            subtitle: const Text('Heure fin'),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _endTime,
              );
              if (picked != null) setState(() => _endTime = picked);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_create_slot_button'),
          onPressed: hasPractitioners ? _onConfirm : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final practitioner = _practitioner;
    if (practitioner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez un praticien.')),
      );
      return;
    }
    final startsAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endsAt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _endTime.hour,
      _endTime.minute,
    );
    if (!endsAt.isAfter(startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("L'heure de fin doit être après l'heure de début."),
        ),
      );
      return;
    }
    Navigator.of(context).pop((
      practitionerId: practitioner.id,
      startsAt: startsAt,
      endsAt: endsAt,
    ));
  }
}
