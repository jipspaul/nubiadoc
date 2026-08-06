import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_bloc.dart';
import 'appointments_event.dart';
import 'appointments_state.dart';

/// Écran "Rendez-vous" côté secrétariat.
///
/// Cloisonnement : aucune donnée clinique (motif clinique, notes) affichée —
/// seules les informations administratives du RDV sont exposées.
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
            return const _AppointmentsSkeleton();
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
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<AppointmentsBloc>()
                  .add(const AppointmentsLoadRequested()),
            );
          }
          return const _InitialView();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers statut / format
// ---------------------------------------------------------------------------

String statusLabel(CabinetAppointmentStatus status) {
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

StatusPillVariant statusVariant(CabinetAppointmentStatus status) {
  switch (status) {
    case CabinetAppointmentStatus.requested:
      return StatusPillVariant.warning;
    case CabinetAppointmentStatus.confirmed:
      return StatusPillVariant.success;
    case CabinetAppointmentStatus.inProgress:
      return StatusPillVariant.info;
    case CabinetAppointmentStatus.completed:
      return StatusPillVariant.info;
    case CabinetAppointmentStatus.cancelled:
      return StatusPillVariant.error;
    case CabinetAppointmentStatus.noShow:
      return StatusPillVariant.error;
  }
}

String _initialsFrom(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '–';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length <= 2 ? p : p.substring(0, 2)).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------

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
              ? const NubiaEmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Aucun rendez-vous',
                  subtitle: 'Aucun rendez-vous pour ce filtre',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _AppointmentCard(appointment: filtered[i]),
                ),
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment});

  final CabinetAppointment appointment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final canConfirm = appointment.status == CabinetAppointmentStatus.requested;

    return Padding(
      key: Key('appointment_${appointment.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: NubiaCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NubiaAvatar(
                  initials: _initialsFrom(appointment.patientName),
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // #4608 : séparateur '·' seulement si le nom du
                        // praticien est disponible, sinon il restait pendant
                        // en tête (« · 06/01 09:00 »).
                        appointment.practitionerName.isEmpty
                            ? _formatDateTime(appointment.startsAt)
                            : '${appointment.practitionerName} · '
                                '${_formatDateTime(appointment.startsAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(
                  label: statusLabel(appointment.status),
                  variant: statusVariant(appointment.status),
                ),
              ],
            ),
            if (canConfirm) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: NubiaButton(
                  key: Key('confirm_${appointment.id}'),
                  label: 'Confirmer',
                  size: NubiaButtonSize.sm,
                  variant: NubiaButtonVariant.secondary,
                  onPressed: () => context.read<AppointmentsBloc>().add(
                        AppointmentConfirmRequested(
                          appointmentId: appointment.id,
                        ),
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
              decoration: const InputDecoration(labelText: 'Nom du patient'),
            ),
            TextField(
              controller: practCtrl,
              decoration: const InputDecoration(labelText: 'Praticien'),
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
                    AppointmentConfirmRequested(appointmentId: idCtrl.text),
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
                      newStartsAt: DateTime.now().add(const Duration(days: 7)),
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      state: NubiaCardState.interactive,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
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
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: NubiaCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: tokens.successFg, size: 40),
                  const SizedBox(width: 12),
                  Text(
                    'Opération effectuée',
                    style: textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoLine(label: 'Patient', value: appointment.patientName),
              const SizedBox(height: 8),
              _InfoLine(
                label: 'Date',
                value: _formatDateTime(appointment.startsAt),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Statut',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusPill(
                    label: statusLabel(appointment.status),
                    variant: statusVariant(appointment.status),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}

/// Skeleton de chargement de la liste des rendez-vous.
class _AppointmentsSkeleton extends StatelessWidget {
  const _AppointmentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('appointments_loading'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: const [
            NubiaSkeletonLoader(width: 72, height: 32, borderRadius: 16),
            SizedBox(width: 8),
            NubiaSkeletonLoader(width: 96, height: 32, borderRadius: 16),
            SizedBox(width: 8),
            NubiaSkeletonLoader(width: 88, height: 32, borderRadius: 16),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 5; i++) ...[
          const NubiaSkeletonLoader(height: 84, borderRadius: 12),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
