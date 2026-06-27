import 'package:flutter/material.dart';

class CreateSlotDialog extends StatefulWidget {
  const CreateSlotDialog({super.key});

  @override
  State<CreateSlotDialog> createState() => _CreateSlotDialogState();
}

class _CreateSlotDialogState extends State<CreateSlotDialog> {
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _startTime = const TimeOfDay(hour: 9, minute: 0);
    _endTime = const TimeOfDay(hour: 9, minute: 30);
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un créneau'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          onPressed: _onConfirm,
          child: const Text('Créer'),
        ),
      ],
    );
  }

  void _onConfirm() {
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
    Navigator.of(context).pop((startsAt: startsAt, endsAt: endsAt));
  }
}
