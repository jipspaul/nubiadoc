import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'patients_bloc.dart';
import 'patients_event.dart';
import 'patients_state.dart';

// ---------------------------------------------------------------------------
// Liste patients
// ---------------------------------------------------------------------------

class PatientsPage extends StatelessWidget {
  const PatientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<PatientsBloc>()..add(const PatientsLoadRequested()),
      child: const _PatientsBody(),
    );
  }
}

class _PatientsBody extends StatefulWidget {
  const _PatientsBody();

  @override
  State<_PatientsBody> createState() => _PatientsBodyState();
}

class _PatientsBodyState extends State<_PatientsBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientsInitial || state is PatientsLoading) {
          return ListView.builder(
            key: const Key('patients_loading'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: 6,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: NubiaSkeletonLoader(height: 56),
            ),
          );
        }
        if (state is PatientsError) {
          return NubiaErrorWidget(
            key: const Key('patients_error'),
            message: state.message,
            onRetry: () =>
                context.read<PatientsBloc>().add(const PatientsLoadRequested()),
          );
        }
        if (state is PatientsLoaded) {
          if (state.patients.isEmpty) {
            return const NubiaEmptyState(
              key: Key('patients_empty'),
              icon: Icons.groups_outlined,
              title: 'Aucun patient',
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
                  key: const Key('patients_search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher un patient',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  key: const Key('patients_list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return ListTile(
                      key: Key('patient_${p.id}'),
                      leading:
                          const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(p.fullName),
                      subtitle: Text(p.email ?? p.phone ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context
                          .read<PatientsBloc>()
                          .add(PatientsDetailLoadRequested(p.id)),
                    );
                  },
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fiche patient (detail)
// ---------------------------------------------------------------------------

class PatientDetailPage extends StatelessWidget {
  final String patientId;
  const PatientDetailPage({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<PatientsBloc>()
        ..add(PatientsDetailLoadRequested(patientId)),
      child: const _PatientDetailBody(),
    );
  }
}

class _PatientDetailBody extends StatelessWidget {
  const _PatientDetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PatientsBloc, PatientsState>(
      listenWhen: (_, s) => s is PatientDetailLoaded && s.notesError != null,
      listener: (context, state) {
        if (state is PatientDetailLoaded && state.notesError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.notesError!)),
          );
        }
      },
      builder: (context, state) {
        if (state is PatientsInitial || state is PatientsLoading) {
          return ListView.builder(
            key: const Key('patient_detail_loading'),
            padding: const EdgeInsets.all(16),
            itemCount: 4,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: NubiaSkeletonLoader(height: 56),
            ),
          );
        }
        if (state is PatientDetailError) {
          return NubiaErrorWidget(
            key: const Key('patient_detail_error'),
            message: state.message,
          );
        }
        if (state is PatientDetailLoaded) {
          return _DetailView(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({required this.state});
  final PatientDetailLoaded state;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.state.patient;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.fullName,
                    key: const Key('patient_name'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (p.email != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text(p.email!, key: const Key('patient_email')),
                      ],
                    ),
                  ],
                  if (p.phone != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text(p.phone!, key: const Key('patient_phone')),
                      ],
                    ),
                  ],
                  if (p.lastVisitAt != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.history_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Dernière visite : ${_formatDate(p.lastVisitAt!)}',
                          key: const Key('patient_last_visit'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Notes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('patient_notes_field'),
            controller: _notesController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Notes du praticien...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.state.notesUpdating)
            const Center(
              key: Key('notes_updating'),
              child: CircularProgressIndicator(),
            )
          else
            FilledButton(
              key: const Key('save_notes_button'),
              onPressed: () => context.read<PatientsBloc>().add(
                    PatientsNotesUpdateRequested(
                      p.id,
                      _notesController.text,
                    ),
                  ),
              child: const Text('Enregistrer les notes'),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
