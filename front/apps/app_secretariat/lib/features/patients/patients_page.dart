import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patients_bloc.dart';
import 'patients_event.dart';
import 'patients_state.dart';

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key});

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    context.read<PatientsBloc>().add(const PatientsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(NubiaL10n.patients),
        actions: [
          IconButton(
            tooltip: NubiaL10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<PatientsBloc>().add(const PatientsLoadRequested()),
          ),
        ],
      ),
      body: BlocBuilder<PatientsBloc, PatientsState>(
        builder: (context, state) {
          if (state is PatientsLoaded) {
            if (state.patients.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.person_outline,
                title: 'Aucun patient',
                subtitle: NubiaL10n.noPatients,
              );
            }
            final filtered = state.patients
                .where((p) =>
                    p.fullName.toLowerCase().contains(_query.toLowerCase()))
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Rechercher un patient',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _PatientTile(patient: filtered[i]),
                  ),
                ),
              ],
            );
          }
          if (state is PatientsError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<PatientsBloc>()
                  .add(const PatientsLoadRequested()),
            );
          }
          return const _LoadingView();
        },
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient});

  final CabinetPatient patient;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(patient.fullName),
      subtitle: patient.email != null ? Text(patient.email!) : null,
      trailing: patient.phone != null
          ? Text(
              patient.phone!,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: NubiaSkeletonLoader(height: 72),
      ),
    );
  }
}
