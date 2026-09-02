import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Résultat renvoyé par [CreateAppointmentSeriesDialog] à la validation —
/// consommé par l'appelant pour dispatcher `AgendaSeriesCreateRequested`
/// (#4088 : `POST /v1/cabinet/appointments/series`).
typedef CreateAppointmentSeriesResult = ({
  String motif,
  List<AppointmentSeriesOccurrence> occurrences,
});

/// Formulaire de création d'une série de RDV liés (ortho, parodonto,
/// chirurgie multi-séances) pour [patient] — la première séance est
/// choisie explicitement, les suivantes sont dérivées d'un intervalle fixe
/// entre séances.
class CreateAppointmentSeriesDialog extends StatefulWidget {
  const CreateAppointmentSeriesDialog({super.key, required this.patient});

  final CabinetPatient patient;

  @override
  State<CreateAppointmentSeriesDialog> createState() =>
      _CreateAppointmentSeriesDialogState();
}

class _CreateAppointmentSeriesDialogState
    extends State<CreateAppointmentSeriesDialog> {
  static const _durationMinutes = 30;
  static const _intervalChoices = [7, 14, 21, 28];
  static const _countChoices = [2, 3, 4, 5, 6, 8];

  final _motifCtrl = TextEditingController();
  DateTime? _firstDate;
  TimeOfDay _firstTime = const TimeOfDay(hour: 9, minute: 0);
  int _occurrenceCount = 3;
  int _intervalDays = 7;

  @override
  void dispose() {
    _motifCtrl.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year} ${_firstTime.format(context)}';

  List<AppointmentSeriesOccurrence> _buildOccurrences() {
    final date = _firstDate;
    if (date == null) return const [];
    final firstStart = DateTime(
      date.year,
      date.month,
      date.day,
      _firstTime.hour,
      _firstTime.minute,
    );
    return List.generate(_occurrenceCount, (i) {
      final startsAt = firstStart.add(Duration(days: _intervalDays * i));
      return AppointmentSeriesOccurrence(
        startsAt: startsAt,
        endsAt: startsAt.add(const Duration(minutes: _durationMinutes)),
      );
    });
  }

  Future<void> _pickFirstDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _firstDate = picked);
  }

  Future<void> _pickFirstTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _firstTime,
    );
    if (picked != null && mounted) setState(() => _firstTime = picked);
  }

  void _confirm() {
    final occurrences = _buildOccurrences();
    if (occurrences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez la date de la 1ère séance.')),
      );
      return;
    }
    Navigator.of(context).pop((
      motif: _motifCtrl.text,
      occurrences: occurrences,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final occurrences = _buildOccurrences();
    return AlertDialog(
      key: const Key('create_series_dialog'),
      title: Text('Série de RDV — ${widget.patient.fullName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('create_series_motif'),
              controller: _motifCtrl,
              decoration:
                  const InputDecoration(labelText: 'Motif (ex. Parodontologie)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(
                _firstDate == null
                    ? 'Choisir la date'
                    : _formatDateTime(_firstDate!),
              ),
              subtitle: const Text('Date de la 1ère séance'),
              onTap: _pickFirstDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: Text(_firstTime.format(context)),
              subtitle: const Text('Heure de la 1ère séance'),
              onTap: _pickFirstTime,
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('create_series_count'),
                    initialValue: _occurrenceCount,
                    decoration: const InputDecoration(labelText: 'Séances'),
                    items: [
                      for (final n in _countChoices)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) =>
                        setState(() => _occurrenceCount = v ?? _occurrenceCount),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const Key('create_series_interval'),
                    initialValue: _intervalDays,
                    decoration:
                        const InputDecoration(labelText: 'Intervalle (jours)'),
                    items: [
                      for (final d in _intervalChoices)
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (v) =>
                        setState(() => _intervalDays = v ?? _intervalDays),
                  ),
                ),
              ],
            ),
            if (occurrences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Séances prévues (${occurrences.length}) :',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              for (final occ in occurrences)
                Text('• ${_formatOccurrence(occ.startsAt)}'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('create_series_submit'),
          onPressed: _confirm,
          child: const Text('Créer la série'),
        ),
      ],
    );
  }

  String _formatOccurrence(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
