import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  @override
  void initState() {
    super.initState();
    context.read<PatientsBloc>().add(const PatientsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<PatientsBloc>().add(const PatientsLoadRequested()),
          ),
        ],
      ),
      body: BlocBuilder<PatientsBloc, PatientsState>(
        builder: (context, state) {
          if (state is PatientsLoaded) {
            final patients = state.patients;
            if (patients.isEmpty) {
              return const Center(child: Text('Aucun patient enregistré.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: patients.length,
              itemBuilder: (_, i) => _PatientTile(patient: patients[i]),
            );
          }
          if (state is PatientsError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
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
