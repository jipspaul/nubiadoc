import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patient_fiche_bloc.dart';

class PatientFiche extends StatelessWidget {
  final CabinetPatient patient;
  const PatientFiche({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PatientFicheBloc(),
      child: _PatientFicheScaffold(patient: patient),
    );
  }
}

class _PatientFicheScaffold extends StatelessWidget {
  final CabinetPatient patient;
  const _PatientFicheScaffold({required this.patient});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientFicheBloc, PatientFicheState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(patient.fullName),
            actions: [
              IconButton(
                key: const Key('toggle_clinical'),
                icon: Icon(
                  state.showClinical ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: state.showClinical
                    ? 'Masquer notes cliniques'
                    : 'Afficher notes cliniques',
                onPressed: () => context
                    .read<PatientFicheBloc>()
                    .add(const ToggleClinicalVisibility()),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.showClinical) ClinicalSection(patient: patient),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ClinicalSection extends StatelessWidget {
  final CabinetPatient patient;
  const ClinicalSection({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('clinical_section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notes cliniques',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (patient.birthDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.cake_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(patient.birthDate!),
                    key: const Key('clinical_birth_date'),
                  ),
                ],
              ),
            ],
            if (patient.lastVisitAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.history_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Dernière visite : ${_formatDate(patient.lastVisitAt!)}',
                    key: const Key('clinical_last_visit'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}
