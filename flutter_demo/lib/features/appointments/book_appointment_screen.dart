import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/appointment_bloc.dart';
import 'bloc/appointment_event.dart';
import 'bloc/appointment_state.dart';

/// Écran de prise de rendez-vous — POST /v1/appointments.
class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController(text: 'Dr Martin');
  final _motifController = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _providerController.dispose();
    _motifController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppointmentBloc, AppointmentState>(
      listener: (context, state) {
        if (state is AppointmentBooked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rendez-vous demandé avec succès')),
          );
          Navigator.of(context).pop();
        }
        if (state is AppointmentError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: BlocBuilder<AppointmentBloc, AppointmentState>(
        builder: (context, state) {
          final loading = state is AppointmentLoading;
          return Scaffold(
            appBar: AppBar(title: const Text('Prendre un RDV')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const Key('field_provider'),
                      controller: _providerController,
                      decoration:
                          const InputDecoration(labelText: 'Praticien'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('field_motif'),
                      controller: _motifController,
                      decoration:
                          const InputDecoration(labelText: 'Motif de consultation'),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 16),
                    _DatePickerRow(
                      selectedDate: _selectedDate,
                      onChanged: (d) => setState(() => _selectedDate = d),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('btn_submit'),
                      onPressed: loading ? null : _submit,
                      child: loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirmer la demande'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AppointmentBloc>().add(
          AppointmentBookRequested(
            providerId: _providerController.text.trim(),
            startsAt: _selectedDate,
            motif: _motifController.text.trim(),
          ),
        );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.selectedDate,
    required this.onChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final day = selectedDate.day.toString().padLeft(2, '0');
    final month = selectedDate.month.toString().padLeft(2, '0');
    final label = '$day/$month/${selectedDate.year}';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date souhaitée', style: textTheme.labelSmall),
              Text(label, style: textTheme.bodyMedium),
            ],
          ),
        ),
        TextButton.icon(
          key: const Key('btn_pick_date'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selectedDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: const Text('Choisir'),
        ),
      ],
    );
  }
}
