import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

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

class _PatientsBody extends StatelessWidget {
  const _PatientsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientsInitial || state is PatientsLoading) {
          return const Center(
            key: Key('patients_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is PatientsError) {
          return _ErrorView(
            key: const Key('patients_error'),
            message: state.message,
            onRetry: () => context
                .read<PatientsBloc>()
                .add(const PatientsLoadRequested()),
          );
        }
        if (state is PatientsLoaded) {
          if (state.patients.isEmpty) {
            return const Center(
              key: Key('patients_empty'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.groups_outlined, size: 48),
                  SizedBox(height: 12),
                  Text('Aucun patient'),
                ],
              ),
            );
          }
          return ListView.builder(
            key: const Key('patients_list'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: state.patients.length,
            itemBuilder: (context, i) {
              final p = state.patients[i];
              return ListTile(
                key: Key('patient_${p.id}'),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(p.fullName),
                subtitle: Text(p.email ?? p.phone ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context
                    .read<PatientsBloc>()
                    .add(PatientsDetailLoadRequested(p.id)),
              );
            },
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
      listenWhen: (_, s) =>
          s is PatientDetailLoaded && s.notesError != null,
      listener: (context, state) {
        if (state is PatientDetailLoaded && state.notesError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.notesError!)),
          );
        }
      },
      builder: (context, state) {
        if (state is PatientsInitial || state is PatientsLoading) {
          return const Center(
            key: Key('patient_detail_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is PatientDetailError) {
          return _ErrorView(
            key: const Key('patient_detail_error'),
            message: state.message,
            onRetry: null,
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

// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ],
      ),
    );
  }
}
