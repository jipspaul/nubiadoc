import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bookable_slots_bloc.dart';
import 'bookable_slots_event.dart';

class CreateSlotDialog extends StatefulWidget {
  const CreateSlotDialog({
    super.key,
    this.initialDate,
    this.initialStart,
    this.initialEnd,
    this.initialCapacity = 1,
  });

  final DateTime? initialDate;
  final TimeOfDay? initialStart;
  final TimeOfDay? initialEnd;
  final int initialCapacity;

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
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _startTime = widget.initialStart ?? const TimeOfDay(hour: 9, minute: 0);
    _endTime = widget.initialEnd ?? const TimeOfDay(hour: 9, minute: 30);
  }

  bool get _isValid {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    return startMinutes < endMinutes;
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

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
    context
        .read<BookableSlotsBloc>()
        .add(CreateSlotRequested(startsAt: startsAt, endsAt: endsAt));
    Navigator.of(context).pop();
  }

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
          key: const Key('create_button'),
          onPressed: _isValid ? _onConfirm : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
