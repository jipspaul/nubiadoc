import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/appointment_card.dart';

/// Appointments screen — onglets "À venir" / "Historique".
///
/// Provides [AppointmentBloc] via [BlocProvider] and delegates rendering to
/// [_AppointmentsBody].
class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<AppointmentBloc>()..add(const AppointmentLoadRequested()),
      child: const _AppointmentsBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentsBody extends StatelessWidget {
  const _AppointmentsBody();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes RDV'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'À venir'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        body: BlocBuilder<AppointmentBloc, AppointmentState>(
          builder: (context, state) {
            if (state is AppointmentInitial || state is AppointmentLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is AppointmentError) {
              return Center(child: Text(state.message));
            }
            if (state is AppointmentLoaded) {
              return _AppointmentTabs(state: state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentTabs extends StatelessWidget {
  const _AppointmentTabs({required this.state});

  final AppointmentLoaded state;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: [
        _AppointmentList(
          appointments: state.upcoming,
          emptyLabel: 'Aucun rendez-vous à venir',
        ),
        _AppointmentList(
          appointments: state.history,
          emptyLabel: 'Aucun historique',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    required this.appointments,
    required this.emptyLabel,
  });

  final List<Appointment> appointments;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return _EmptyAppointments(label: emptyLabel);
    }
    return ListView.builder(
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final appt = appointments[index];
        return AppointmentCard(
          appointment: appt,
          onTap: () => context.push(
            RouteNames.appointmentDetail.replaceFirst(':id', appt.id),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyAppointments extends StatelessWidget {
  const _EmptyAppointments({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
