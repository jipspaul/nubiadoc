import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_appointment_by_id_use_case.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/checkin_bloc.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Full appointment detail screen.
///
/// Loads the appointment by [id], then displays:
/// - practitioner + date/motif info
/// - action buttons: check-in, modify, cancel
///
/// Deep-link target: nubia://appointments/:id
///
/// [checkinBloc] and [getAppointmentByIdUseCase] are optional; when omitted,
/// they are resolved from [getIt]. Pass them explicitly in tests.
class AppointmentDetailScreen extends StatelessWidget {
  const AppointmentDetailScreen({
    super.key,
    required this.id,
    this.checkinBloc,
    this.getAppointmentByIdUseCase,
  });

  final String id;
  final CheckinBloc? checkinBloc;
  final GetAppointmentByIdUseCase? getAppointmentByIdUseCase;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => checkinBloc ?? getIt<CheckinBloc>(),
      child: _AppointmentDetailBody(
        id: id,
        useCase: getAppointmentByIdUseCase ?? getIt<GetAppointmentByIdUseCase>(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentDetailBody extends StatefulWidget {
  const _AppointmentDetailBody({required this.id, required this.useCase});

  final String id;
  final GetAppointmentByIdUseCase useCase;

  @override
  State<_AppointmentDetailBody> createState() => _AppointmentDetailBodyState();
}

class _AppointmentDetailBodyState extends State<_AppointmentDetailBody> {
  Appointment? _appointment;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.useCase(widget.id);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (appt) => setState(() {
        _appointment = appt;
        _loading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CheckinBloc, CheckinState>(
      listener: _handleCheckinState,
      child: Scaffold(
        appBar: AppBar(title: const Text('Détail RDV')),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final appt = _appointment!;
    return _AppointmentDetailContent(appointment: appt);
  }

  void _handleCheckinState(BuildContext context, CheckinState state) {
    if (state is CheckinSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in effectué !')),
      );
      setState(() => _appointment = state.appointment);
    }
    if (state is CheckinFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    }
  }
}

// ---------------------------------------------------------------------------

class _AppointmentDetailContent extends StatelessWidget {
  const _AppointmentDetailContent({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppointmentInfoCard(appointment: appointment),
          const SizedBox(height: 24),
          _AppointmentActions(appointment: appointment),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentInfoCard extends StatelessWidget {
  const _AppointmentInfoCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final dateLabel = DateFormat("EEE d MMM yyyy 'à' HH'h'mm", 'fr')
        .format(appointment.startsAt);
    final durationLabel = '${appointment.duration.inMinutes} min';

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(appointment.motif, style: textTheme.titleMedium),
                ),
                const SizedBox(width: 8),
                _AppointmentStatusChip(
                  status: appointment.status,
                  tokens: tokens,
                  colorScheme: colorScheme,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _IconRow(
              icon: Icons.person_outline,
              label:
                  '${appointment.practitionerName} · ${appointment.practitionerSpecialty}',
              color: tokens?.textTertiary ?? colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            _IconRow(
              icon: Icons.calendar_today_outlined,
              label: '$dateLabel · $durationLabel',
              color: colorScheme.primary,
            ),
            if (appointment.cabinetAddress != null) ...[
              const SizedBox(height: 4),
              _IconRow(
                icon: Icons.location_on_outlined,
                label: appointment.cabinetAddress!,
                color: tokens?.textTertiary ?? colorScheme.onSurfaceVariant,
              ),
            ],
            if (appointment.cabinetPhone != null) ...[
              const SizedBox(height: 4),
              _IconRow(
                icon: Icons.phone_outlined,
                label: appointment.cabinetPhone!,
                color: tokens?.textTertiary ?? colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentActions extends StatelessWidget {
  const _AppointmentActions({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final canCheckin = appointment.status == AppointmentStatus.confirmed &&
        appointment.startsAt.isAfter(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canCheckin) _CheckinButton(appointment: appointment),
        if (appointment.canModify) ...[
          const SizedBox(height: 12),
          _ModifyButton(appointment: appointment),
        ],
        if (appointment.canCancel) ...[
          const SizedBox(height: 12),
          _CancelButton(appointment: appointment),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CheckinButton extends StatelessWidget {
  const _CheckinButton({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CheckinBloc, CheckinState>(
      builder: (context, state) {
        final submitting = state is CheckinInProgress;
        return FilledButton.icon(
          onPressed: submitting
              ? null
              : () => context
                  .read<CheckinBloc>()
                  .add(CheckinRequested(appointment.id)),
          icon: submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('Effectuer le check-in'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ModifyButton extends StatelessWidget {
  const _ModifyButton({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => context.push(
        RouteNames.appointmentModify.replaceFirst(':id', appointment.id),
        extra: appointment,
      ),
      icon: const Icon(Icons.edit_calendar_outlined),
      label: const Text('Modifier le rendez-vous'),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentStatusChip extends StatelessWidget {
  const _AppointmentStatusChip({
    required this.status,
    required this.tokens,
    required this.colorScheme,
  });

  final AppointmentStatus status;
  final NubiaTokens? tokens;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (label, fg, bg) = _chipStyle();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  (String, Color, Color) _chipStyle() {
    final t = tokens;
    switch (status) {
      case AppointmentStatus.confirmed:
        return ('Confirmé', t?.successFg ?? colorScheme.primary,
            t?.successBg ?? colorScheme.primaryContainer);
      case AppointmentStatus.requested:
        return ('En attente', t?.warningFg ?? colorScheme.secondary,
            t?.warningBg ?? colorScheme.secondaryContainer);
      case AppointmentStatus.cancelled:
        return ('Annulé', t?.dangerFg ?? colorScheme.error,
            t?.dangerBg ?? colorScheme.errorContainer);
      case AppointmentStatus.completed:
        return ('Terminé', t?.textTertiary ?? colorScheme.onSurfaceVariant,
            t?.primarySubtleBg ?? colorScheme.surfaceContainerHighest);
      case AppointmentStatus.noShow:
        return ('Absent', t?.dangerFg ?? colorScheme.error,
            t?.dangerBg ?? colorScheme.errorContainer);
    }
  }
}

// ---------------------------------------------------------------------------

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
        side: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      onPressed: () => context.push(
        RouteNames.appointmentCancel.replaceFirst(':id', appointment.id),
        extra: appointment,
      ),
      icon: const Icon(Icons.cancel_outlined),
      label: const Text('Annuler le rendez-vous'),
    );
  }
}
