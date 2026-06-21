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
  late DateTime? _date;
  late TimeOfDay? _startTime;
  late TimeOfDay? _endTime;
  late int _capacity;
  late final TextEditingController _capacityCtrl;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _startTime = widget.initialStart;
    _endTime = widget.initialEnd;
    _capacity = widget.initialCapacity;
    _capacityCtrl = TextEditingController(text: '${widget.initialCapacity}');
  }

  @override
  void dispose() {
    _capacityCtrl.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_date == null || _startTime == null || _endTime == null) return false;
    if (_capacity < 1) return false;
    final startMins = _startTime!.hour * 60 + _startTime!.minute;
    final endMins = _endTime!.hour * 60 + _endTime!.minute;
    return startMins < endMins;
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un créneau'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('date_button'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                _date == null ? 'Sélectionner une date' : _formatDate(_date!),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('start_time_button'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: Text(
                _startTime == null
                    ? 'Heure début'
                    : _startTime!.format(context),
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime:
                      _startTime ?? const TimeOfDay(hour: 9, minute: 0),
                );
                if (picked != null) setState(() => _startTime = picked);
              },
            ),
            ListTile(
              key: const Key('end_time_button'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_filled_outlined),
              title: Text(
                _endTime == null ? 'Heure fin' : _endTime!.format(context),
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime:
                      _endTime ?? const TimeOfDay(hour: 10, minute: 0),
                );
                if (picked != null) setState(() => _endTime = picked);
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                key: const Key('capacity_field'),
                controller: _capacityCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Capacité',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    setState(() => _capacity = int.tryParse(v) ?? 0),
              ),
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
          key: const Key('create_button'),
          onPressed: _isValid
              ? () {
                  context.read<BookableSlotsBloc>().add(CreateSlotRequested(
                        date: _date!,
                        startTime: _startTime!,
                        endTime: _endTime!,
                        capacity: _capacity,
                      ));
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
