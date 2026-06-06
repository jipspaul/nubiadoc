import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/slot_grid.dart';

/// Screen for booking a new appointment.
///
/// Consumes [BookingBloc]. Caller must provide the bloc via [BlocProvider].
class BookingScreen extends StatelessWidget {
  const BookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookingBloc, BookingState>(
      listener: _handleStateChange,
      child: Scaffold(
        appBar: AppBar(title: const Text('Prendre un rendez-vous')),
        body: BlocBuilder<BookingBloc, BookingState>(
          builder: (context, state) {
            if (state is BookingInitial || state is BookingLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is BookingError) {
              return Center(child: Text(state.message));
            }
            if (state is BookingLoaded) {
              return _BookingForm(state: state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  void _handleStateChange(BuildContext context, BookingState state) {
    if (state is BookingSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous confirmé !')),
      );
      Navigator.of(context).pop(state.appointment);
    }
    if (state is BookingError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Internal form widget (keeps BookingScreen under 50 lines)
// ---------------------------------------------------------------------------

class _BookingForm extends StatelessWidget {
  const _BookingForm({required this.state});

  final BookingLoaded state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Créneaux disponibles',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SlotGrid(
            slots: state.slots,
            selectedSlot: state.selectedSlot,
            onSlotTap: (slot) => context
                .read<BookingBloc>()
                .add(BookingSlotSelected(slot)),
          ),
          const SizedBox(height: 24),
          Text(
            'Motif de consultation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _MotifField(motif: state.motif),
          const SizedBox(height: 32),
          _ConfirmButton(state: state),
        ],
      ),
    );
  }
}

class _MotifField extends StatelessWidget {
  const _MotifField({required this.motif});

  final String motif;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: motif,
      maxLines: 3,
      decoration: const InputDecoration(
        hintText: 'Ex. : Contrôle annuel, douleur dentaire…',
        border: OutlineInputBorder(),
      ),
      onChanged: (value) =>
          context.read<BookingBloc>().add(BookingMotifChanged(value)),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.state});

  final BookingLoaded state;

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        state.selectedSlot != null && state.motif.trim().isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: state.submitting || !canSubmit
            ? null
            : () =>
                context.read<BookingBloc>().add(const BookingSubmitted()),
        child: state.submitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Confirmer le rendez-vous'),
      ),
    );
  }
}
