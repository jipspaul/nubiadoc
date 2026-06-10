import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'appointment_detail_screen.dart';
import 'bloc/appointment_bloc.dart';
import 'bloc/appointment_event.dart';
import 'bloc/appointment_state.dart';
import 'book_appointment_screen.dart';
import 'models/appointment.dart';
import 'widgets/appointment_card.dart';

/// Page principale des rendez-vous — onglets « À venir » et « Historique ».
class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes rendez-vous'),
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('tab_upcoming'), text: 'À venir'),
              Tab(key: Key('tab_history'), text: 'Historique'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('fab_book'),
          onPressed: () => _openBooking(context),
          icon: const Icon(Icons.add),
          label: const Text('Prendre RDV'),
        ),
        body: const TabBarView(
          children: [
            _AppointmentsTab(tab: AppointmentTab.upcoming),
            _AppointmentsTab(tab: AppointmentTab.history),
          ],
        ),
      ),
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

/// Onglet d'une liste de RDV filtrée par [tab].
class _AppointmentsTab extends StatefulWidget {
  const _AppointmentsTab({required this.tab});

  final AppointmentTab tab;

  @override
  State<_AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<_AppointmentsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    context
        .read<AppointmentBloc>()
        .add(AppointmentLoadRequested(tab: widget.tab));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<AppointmentBloc, AppointmentState>(
      builder: (context, state) {
        return switch (state) {
          AppointmentLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          AppointmentListLoaded(:final appointments, :final tab)
              when tab == widget.tab =>
            _AppointmentList(appointments: appointments),
          AppointmentCancelling(:final appointments) =>
            _AppointmentList(appointments: appointments, busy: true),
          AppointmentError(:final message) => _ErrorView(
              message: message,
              onRetry: () => context.read<AppointmentBloc>().add(
                    AppointmentLoadRequested(tab: widget.tab),
                  ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        };
      },
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({required this.appointments, this.busy = false});

  final List<Appointment> appointments;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        key: const Key('empty_list'),
        child: Text(
          'Aucun rendez-vous',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(bottom: 88, top: 8),
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
