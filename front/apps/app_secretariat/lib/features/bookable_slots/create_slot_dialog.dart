import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bookable_slots_bloc.dart';
import 'bookable_slots_event.dart';

class CreateSlotDialog extends StatefulWidget {
  const CreateSlotDialog({super.key});

  @override
  State<CreateSlotDialog> createState() => _CreateSlotDialogState();
}

class _CreateSlotDialogState extends State<CreateSlotDialog> {
  DateTime _date = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 9, minute: 30);
  int _capacity = 1;

  final _capacityController = TextEditingController(text: '1');

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    return startMinutes < endMinutes && _capacity >= 1;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un créneau'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: const Key('slot_date_field'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(_formatDate(_date)),
              subtitle: const Text('Date'),
              onTap: _pickDate,
            ),
            ListTile(
              key: const Key('slot_start_time_field'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_outlined),
              title: Text(_startTime.format(context)),
              subtitle: const Text('Heure début'),
              onTap: _pickStartTime,
            ),
            ListTile(
              key: const Key('slot_end_time_field'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_filled_outlined),
              title: Text(_endTime.format(context)),
              subtitle: const Text('Heure fin'),
              onTap: _pickEndTime,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('slot_capacity_field'),
              controller: _capacityController,
              decoration: const InputDecoration(
                labelText: 'Capacité',
                prefixIcon: Icon(Icons.people_outline),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                setState(() => _capacity = int.tryParse(v) ?? 0);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('slot_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('slot_create_button'),
          onPressed: _isValid
              ? () {
                  context.read<BookableSlotsBloc>().add(
                        CreateSlotRequested(
                          date: _date,
                          startTime: _startTime,
                          endTime: _endTime,
                          capacity: _capacity,
                        ),
                      );
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
