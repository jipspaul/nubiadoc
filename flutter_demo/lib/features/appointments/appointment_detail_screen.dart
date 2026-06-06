import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/appointment_bloc.dart';
import 'bloc/appointment_event.dart';
import 'bloc/appointment_state.dart';
import 'models/appointment.dart';
import 'widgets/appointment_status_chip.dart';

/// Écran détail d'un rendez-vous — GET /v1/appointments/{id}.
///
/// Permet également l'annulation via POST /v1/appointments/{id}/cancel.
class AppointmentDetailScreen extends StatefulWidget {
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  State<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    context
        .read<AppointmentBloc>()
        .add(AppointmentDetailRequested(id: widget.appointmentId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AppointmentBloc, AppointmentState>(
      listener: (context, state) {
        if (state is AppointmentListLoaded || state is AppointmentError) {
          // Après annulation ou erreur, revenir à la liste.
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Détail RDV')),
          body: switch (state) {
            AppointmentLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            AppointmentDetailLoaded(:final appointment) =>
              _DetailBody(appointment: appointment),
            AppointmentCancelling() => const Center(
                child: CircularProgressIndicator(),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canCancel = appointment.status == AppointmentStatus.confirmed ||
        appointment.status == AppointmentStatus.requested;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(appointment.providerName, style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          AppointmentStatusChip(status: appointment.status),
          const SizedBox(height: 20),
          _InfoRow(
            icon: Icons.medical_services_outlined,
            label: 'Motif',
            value: appointment.motif,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.schedule,
            label: 'Date',
            value: _formatDate(appointment.startsAt),
          ),
          if (appointment.address != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Adresse',
              value: appointment.address!,
            ),
          ],
          const Spacer(),
          if (canCancel)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('btn_cancel'),
                onPressed: () => context.read<AppointmentBloc>().add(
                      AppointmentCancelRequested(id: appointment.id),
                    ),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annuler ce rendez-vous'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day/$month/${d.year} à $hour:$min';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: textTheme.labelSmall),
              Text(value, style: textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
