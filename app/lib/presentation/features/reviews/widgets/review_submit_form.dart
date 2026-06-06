import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Form for submitting a new review.
///
/// Exposes [onSubmit] called with (appointmentId, rating, comment) when the
/// user confirms. Caller is responsible for providing the [Appointment] list
/// and wiring [onSubmit] to the Bloc.
class ReviewSubmitForm extends StatefulWidget {
  const ReviewSubmitForm({
    super.key,
    required this.honoredAppointments,
    required this.onSubmit,
    this.isSubmitting = false,
  });

  final List<Appointment> honoredAppointments;
  final void Function(String appointmentId, int rating, String? comment)
      onSubmit;
  final bool isSubmitting;

  @override
  State<ReviewSubmitForm> createState() => _ReviewSubmitFormState();
}

class _ReviewSubmitFormState extends State<ReviewSubmitForm> {
  String? _selectedAppointmentId;
  int _rating = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedAppointmentId != null &&
      _rating > 0 &&
      !widget.isSubmitting;

  void _submit() {
    if (!_canSubmit) return;
    widget.onSubmit(
      _selectedAppointmentId!,
      _rating,
      _commentController.text.trim().isEmpty
          ? null
          : _commentController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rendez-vous concerné', style: textTheme.labelLarge),
        const SizedBox(height: 8),
        _AppointmentPicker(
          appointments: widget.honoredAppointments,
          selectedId: _selectedAppointmentId,
          onChanged: (id) => setState(() => _selectedAppointmentId = id),
        ),
        const SizedBox(height: 16),
        Text('Note', style: textTheme.labelLarge),
        const SizedBox(height: 8),
        _RatingPicker(
          rating: _rating,
          onChanged: (r) => setState(() => _rating = r),
        ),
        const SizedBox(height: 16),
        Text('Commentaire (optionnel)', style: textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Partagez votre expérience…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('submit_review'),
            onPressed: _canSubmit ? _submit : null,
            child: widget.isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Envoyer mon avis'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentPicker extends StatelessWidget {
  const _AppointmentPicker({
    required this.appointments,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Appointment> appointments;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Text(
        'Aucun rendez-vous honoré disponible.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).extension<NubiaTokens>()!.textTertiary,
            ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      hint: const Text('Sélectionner un rendez-vous'),
      items: appointments
          .map(
            (a) => DropdownMenuItem(
              value: a.id,
              child: Text(
                '${a.practitionerName} — ${a.motif}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------

class _RatingPicker extends StatelessWidget {
  const _RatingPicker({
    required this.rating,
    required this.onChanged,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).extension<NubiaTokens>()!.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => IconButton(
          key: Key('star_${i + 1}'),
          icon: Icon(
            i < rating ? Icons.star : Icons.star_border,
            color: color,
          ),
          onPressed: () => onChanged(i + 1),
        ),
      ),
    );
  }
}
