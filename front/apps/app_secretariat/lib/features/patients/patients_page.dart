import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patients_bloc.dart';
import 'patients_event.dart';
import 'patients_state.dart';

/// Écran "Patients" côté secrétariat — liste + fiche administrative.
///
/// Cloisonnement : ZÉRO donnée clinique. Seules les informations
/// administratives (identité, contact, dernière visite) sont exposées.
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _PatientRow(patient: filtered[i]),
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
          // PatientsInitial, PatientsLoading
          return const _PatientsSkeleton();
        },
      ),
    );
  }
}

/// Initiales à partir du nom complet (fallback avatar).
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

/// Formate une date en « jj/mm/aaaa ».
String _formatDate(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/'
    '${dt.month.toString().padLeft(2, '0')}/'
    '${dt.year}';

/// Ligne patient : avatar + nom + infos administratives + chevron.
class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.patient});

  final CabinetPatient patient;

  @override
  Widget build(BuildContext context) {
    // Sous-titre : informations administratives uniquement (contact). Aucune
    // donnée clinique — cloisonnement secrétariat.
    final parts = <String>[
      if (patient.phone != null && patient.phone!.isNotEmpty) patient.phone!,
      if (patient.email != null && patient.email!.isNotEmpty) patient.email!,
    ];

    return ListRow(
      leading:
          NubiaAvatar(initials: _initialsFrom(patient.fullName), radius: 20),
      title: patient.fullName,
      subtitle: parts.isEmpty ? null : parts.join(' · '),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPatientSheet(context, patient),
    );
  }
}

/// Ouvre la fiche patient (informations administratives) dans une carte DS.
void _showPatientSheet(BuildContext context, CabinetPatient patient) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _PatientSheet(patient: patient),
  );
}

class _PatientSheet extends StatelessWidget {
  const _PatientSheet({required this.patient});

  final CabinetPatient patient;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // Uniquement des champs administratifs (cloisonnement : zéro clinique).
    final rows = <(IconData, String, String)>[
      if (patient.birthDate != null)
        (Icons.cake_outlined, 'Naissance', _formatDate(patient.birthDate!)),
      if (patient.phone != null && patient.phone!.isNotEmpty)
        (Icons.phone_outlined, 'Téléphone', patient.phone!),
      if (patient.email != null && patient.email!.isNotEmpty)
        (Icons.mail_outline, 'Email', patient.email!),
      if (patient.socialSecurityNumber != null &&
          patient.socialSecurityNumber!.isNotEmpty)
        (
          Icons.badge_outlined,
          'N° sécurité sociale',
          patient.socialSecurityNumber!
        ),
      if (patient.lastVisitAt != null)
        (Icons.history, 'Dernière visite', _formatDate(patient.lastVisitAt!)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                NubiaAvatar(
                  initials: _initialsFrom(patient.fullName),
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    patient.fullName,
                    style: textTheme.titleLarge?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            NubiaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(rows[i].$1, size: 20, color: cs.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rows[i].$2,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                rows[i].$3,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (rows.isEmpty)
                    Text(
                      'Aucune information administrative disponible.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton de chargement de la liste patients (barre de recherche + lignes).
class _PatientsSkeleton extends StatelessWidget {
  const _PatientsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('patients_loading'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const NubiaSkeletonLoader(height: 48, borderRadius: 8),
        const SizedBox(height: 16),
        for (var i = 0; i < 8; i++) ...[
          const NubiaSkeletonLoader(height: 56, borderRadius: 12),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
