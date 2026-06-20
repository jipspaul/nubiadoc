import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_bloc.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    context.read<AppointmentsBloc>().add(const AppointmentsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<AppointmentsBloc>()
                .add(const AppointmentsLoadRequested()),
          ),
        ],
      ),
      body: BlocBuilder<AppointmentsBloc, AppointmentsState>(
        builder: (context, state) {
          if (state is AppointmentsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AppointmentsLoaded) {
            return _LoadedView(
              appointments: state.appointments,
              statusFilter: _statusFilter,
              onFilterChanged: (f) => setState(() => _statusFilter = f),
            );
          }
          if (state is AppointmentSuccess) {
            return _SuccessView(appointment: state.appointment);
          }
          if (state is AppointmentsError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const _InitialView();
        },
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({
    required this.appointments,
    required this.statusFilter,
    required this.onFilterChanged,
  });

  final List<CabinetAppointment> appointments;
  final String statusFilter;
  final ValueChanged<String> onFilterChanged;

  static const _chips = [
    ('Tous', 'all'),
    ('Confirmé', 'confirmed'),
    ('En attente', 'requested'),
    ('Annulé', 'cancelled'),
  ];

  List<CabinetAppointment> get _filtered {
    if (statusFilter == 'all') return appointments;
    return appointments.where((a) {
      switch (statusFilter) {
        case 'confirmed':
          return a.status == CabinetAppointmentStatus.confirmed;
        case 'requested':
          return a.status == CabinetAppointmentStatus.requested;
        case 'cancelled':
          return a.status == CabinetAppointmentStatus.cancelled;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (label, value) in _chips)
                FilterChip(
                  label: Text(label),
                  selected: statusFilter == value,
                  onSelected: (_) => onFilterChanged(value),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Aucun rendez-vous'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _AppointmentTile(appointment: filtered[i]),
                ),
        ),
      ],
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment});

  final CabinetAppointment appointment;

  String _statusLabel(CabinetAppointmentStatus status) {
    switch (status) {
      case CabinetAppointmentStatus.requested:
        return 'En attente';
      case CabinetAppointmentStatus.confirmed:
        return 'Confirmé';
      case CabinetAppointmentStatus.inProgress:
        return 'En cours';
      case CabinetAppointmentStatus.completed:
        return 'Terminé';
      case CabinetAppointmentStatus.cancelled:
        return 'Annulé';
      case CabinetAppointmentStatus.noShow:
        return 'Absent';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.event_outlined),
      title: Text(appointment.patientName),
      subtitle: Text(appointment.practitionerName),
      trailing: Chip(
        label: Text(
          _statusLabel(appointment.status),
          style: const TextStyle(fontSize: 12),
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _InitialView extends StatelessWidget {
  const _InitialView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ActionCard(
          title: 'Créer un rendez-vous',
          icon: Icons.add_circle_outline,
          onTap: () => _showCreateDialog(context),
        ),
        const SizedBox(height: 12),
        _ActionCard(
          title: 'Confirmer un rendez-vous',
          icon: Icons.check_circle_outline,
          onTap: () => _showConfirmDialog(context),
        ),
        const SizedBox(height: 12),
        _ActionCard(
          title: 'Reprogrammer un rendez-vous',
          icon: Icons.schedule,
          onTap: () => _showRescheduleDialog(context),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context) {
    final patientCtrl = TextEditingController();
    final practCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau rendez-vous'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: patientCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nom du patient'),
            ),
            TextField(
              controller: practCtrl,
              decoration:
                  const InputDecoration(labelText: 'Praticien'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final appt = CabinetAppointment(
                id: '',
                cabinetId: '',
                patientId: '',
                patientName: patientCtrl.text,
                practitionerId: '',
                practitionerName: practCtrl.text,
                startsAt: DateTime.now().add(const Duration(days: 1)),
                duration: const Duration(minutes: 30),
                motif: '',
                status: CabinetAppointmentStatus.requested,
              );
              context
                  .read<AppointmentsBloc>()
                  .add(AppointmentCreateRequested(appointment: appt));
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(BuildContext context) {
    final idCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer le rendez-vous'),
        content: TextField(
          controller: idCtrl,
          decoration: const InputDecoration(labelText: 'ID du rendez-vous'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AppointmentsBloc>().add(
                    AppointmentConfirmRequested(
                        appointmentId: idCtrl.text),
                  );
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _showRescheduleDialog(BuildContext context) {
    final idCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reprogrammer le rendez-vous'),
        content: TextField(
          controller: idCtrl,
          decoration: const InputDecoration(labelText: 'ID du rendez-vous'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AppointmentsBloc>().add(
                    AppointmentRescheduleRequested(
                      appointmentId: idCtrl.text,
                      newStartsAt:
                          DateTime.now().add(const Duration(days: 7)),
                    ),
                  );
            },
            child: const Text('Reprogrammer'),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Affiche le résultat d'une opération RDV — sans champ clinique.
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.appointment});

  final CabinetAppointment appointment;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Opération effectuée',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Patient : ${appointment.patientName}'),
                Text(
                  'Date : ${_formatDate(appointment.startsAt)}',
                ),
                Text('Statut : ${_statusLabel(appointment.status)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  String _statusLabel(CabinetAppointmentStatus status) {
    switch (status) {
      case CabinetAppointmentStatus.requested:
        return 'Demandé';
      case CabinetAppointmentStatus.confirmed:
        return 'Confirmé';
      case CabinetAppointmentStatus.inProgress:
        return 'En cours';
      case CabinetAppointmentStatus.completed:
        return 'Terminé';
      case CabinetAppointmentStatus.cancelled:
        return 'Annulé';
      case CabinetAppointmentStatus.noShow:
        return 'Absent';
    }
  }
}
