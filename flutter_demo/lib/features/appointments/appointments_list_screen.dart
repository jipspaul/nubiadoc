import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'appointment_detail_screen.dart';
import 'bloc/appointment_bloc.dart';
import 'bloc/appointment_event.dart';
import 'bloc/appointment_state.dart';
import 'book_appointment_screen.dart';
import 'models/appointment.dart';
import 'widgets/appointment_card.dart';

/// Écran liste des rendez-vous patient — GET /v1/appointments.
class AppointmentsListScreen extends StatelessWidget {
  const AppointmentsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppointmentBloc, AppointmentState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Mes rendez-vous')),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('fab_book'),
            onPressed: () => _openBooking(context),
            icon: const Icon(Icons.add),
            label: const Text('Prendre RDV'),
          ),
          body: switch (state) {
            AppointmentInitial() => const _LoadTrigger(),
            AppointmentLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            AppointmentListLoaded(:final appointments) =>
              _AppointmentList(appointments: appointments),
            AppointmentCancelling(:final appointments) =>
              _AppointmentList(appointments: appointments, busy: true),
            AppointmentDetailLoaded() => const _LoadTrigger(),
            AppointmentBooked() => const _LoadTrigger(),
            AppointmentError(:final message) => _ErrorView(
                message: message,
                onRetry: () => context
                    .read<AppointmentBloc>()
                    .add(const AppointmentLoadRequested()),
              ),
          },
        );
      },
    );
  }

  void _openBooking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: context.read<AppointmentBloc>(),
          child: const BookAppointmentScreen(),
        ),
      ),
    );
  }
}

class _LoadTrigger extends StatefulWidget {
  const _LoadTrigger();

  @override
  State<_LoadTrigger> createState() => _LoadTriggerState();
}

class _LoadTriggerState extends State<_LoadTrigger> {
  @override
  void initState() {
    super.initState();
    context.read<AppointmentBloc>().add(const AppointmentLoadRequested());
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({required this.appointments, this.busy = false});

  final List<Appointment> appointments;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return const Center(child: Text('Aucun rendez-vous'));
    }
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: appointments.length,
          itemBuilder: (context, i) {
            final apt = appointments[i];
            return AppointmentCard(
              appointment: apt,
              onTap: () => _openDetail(context, apt.id),
            );
          },
        ),
        if (busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  void _openDetail(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: context.read<AppointmentBloc>(),
          child: AppointmentDetailScreen(appointmentId: id),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
