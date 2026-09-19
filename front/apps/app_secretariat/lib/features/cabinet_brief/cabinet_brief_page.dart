import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'cabinet_brief_bloc.dart';
import 'cabinet_brief_event.dart';
import 'cabinet_brief_state.dart';

const _views = [
  ('day', 'Jour'),
  ('week', 'Semaine'),
  ('prostheses', 'Prothèses'),
];

/// Page « Brief » (#7191) : lecture + impression/partage du brief cabinet
/// jour/semaine/prothèses, accessible depuis l'agenda praticien.
class CabinetBriefPage extends StatelessWidget {
  const CabinetBriefPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('cabinet_brief_scaffold'),
      appBar: AppBar(
        title: const Text('Brief du cabinet'),
        actions: [
          BlocBuilder<CabinetBriefBloc, CabinetBriefState>(
            builder: (context, state) {
              final loaded = state is CabinetBriefLoaded ? state : null;
              return IconButton(
                key: const Key('cabinet_brief_pdf_button'),
                tooltip: 'Imprimer / partager',
                icon: loaded != null && loaded.isExportingPdf
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                onPressed: loaded != null && !loaded.isExportingPdf
                    ? () => context
                        .read<CabinetBriefBloc>()
                        .add(const CabinetBriefPdfRequested())
                    : null,
              );
            },
          ),
          IconButton(
            key: const Key('cabinet_brief_refresh'),
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final state = context.read<CabinetBriefBloc>().state;
              final view = state is CabinetBriefLoaded ? state.view : 'day';
              final date = state is CabinetBriefLoaded ? state.date : null;
              context
                  .read<CabinetBriefBloc>()
                  .add(CabinetBriefLoadRequested(view: view, date: date));
            },
          ),
        ],
      ),
      body: const CabinetBriefBody(),
    );
  }
}

/// Corps de l'écran — consommable dans une route dédiée.
class CabinetBriefBody extends StatelessWidget {
  const CabinetBriefBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CabinetBriefBloc, CabinetBriefState>(
      listenWhen: (prev, curr) =>
          curr is CabinetBriefLoaded &&
          ((curr.pdfBytes != null &&
                  (prev is! CabinetBriefLoaded || prev.pdfBytes == null)) ||
              (curr.pdfError != null &&
                  (prev is! CabinetBriefLoaded || prev.pdfError == null))),
      listener: (context, state) async {
        final loaded = state as CabinetBriefLoaded;
        if (loaded.pdfBytes != null) {
          final filename = loaded.pdfFilename ?? 'brief.pdf';
          final bytes = Uint8List.fromList(loaded.pdfBytes!);
          if (_isDesktopPlatform) {
            // Desktop : la feuille de partage système n'est pas implémentée
            // sur Linux — même choix que `patient_fiche.dart` (#4983).
            await GetIt.instance<FilePickerService>()
                .saveFile(bytes: bytes, fileName: filename);
          } else {
            await Share.shareXFiles(
              [
                XFile.fromData(
                  bytes,
                  name: filename,
                  mimeType: 'application/pdf',
                ),
              ],
              subject: 'Brief du cabinet',
            );
          }
          if (context.mounted) {
            context
                .read<CabinetBriefBloc>()
                .add(const CabinetBriefPdfConsumed());
          }
        }
        if (loaded.pdfError != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loaded.pdfError!)),
          );
          context.read<CabinetBriefBloc>().add(const CabinetBriefPdfConsumed());
        }
      },
      builder: (context, state) {
        if (state is CabinetBriefInitial || state is CabinetBriefLoading) {
          return const _CabinetBriefSkeleton(key: Key('cabinet_brief_loading'));
        }
        if (state is CabinetBriefError) {
          return NubiaErrorWidget(
            key: const Key('cabinet_brief_error'),
            message: state.message,
            onRetry: () => context
                .read<CabinetBriefBloc>()
                .add(const CabinetBriefLoadRequested(view: 'day')),
          );
        }
        if (state is CabinetBriefLoaded) {
          return _LoadedBrief(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

class _LoadedBrief extends StatelessWidget {
  const _LoadedBrief({required this.state});
  final CabinetBriefLoaded state;

  @override
  Widget build(BuildContext context) {
    final brief = state.brief;
    return Column(
      children: [
        _ViewSelector(selected: state.view, date: state.date),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: const Key('cabinet_brief_list'),
            padding: const EdgeInsets.all(16),
            children: [
              _AppointmentsSection(
                groups: brief.appointmentsByPractitioner,
              ),
              const SizedBox(height: 16),
              _NewPatientsSection(patients: brief.newPatients),
              const SizedBox(height: 16),
              _PlannedActsSection(acts: brief.plannedActs),
              const SizedBox(height: 16),
              _ProsthesesSection(prostheses: brief.prosthesesToFit),
              const SizedBox(height: 16),
              _OpenTasksSection(tasks: brief.openTasks),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewSelector extends StatelessWidget {
  const _ViewSelector({required this.selected, required this.date});
  final String selected;
  final String? date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        key: const Key('cabinet_brief_view_selector'),
        children: [
          for (final (view, label) in _views) ...[
            NubiaChip(
              key: Key('cabinet_brief_view_$view'),
              label: label,
              variant: NubiaChipVariant.choice,
              selected: selected == view,
              onTap: () => context.read<CabinetBriefBloc>().add(
                    CabinetBriefLoadRequested(view: view, date: date),
                  ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.isEmpty,
    required this.children,
  });

  final String title;
  final String emptyLabel;
  final bool isEmpty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: 8),
          if (isEmpty)
            Text(
              emptyLabel,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _AppointmentsSection extends StatelessWidget {
  const _AppointmentsSection({required this.groups});
  final List<BriefPractitionerAppointments> groups;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _SectionCard(
      key: const Key('cabinet_brief_appointments_section'),
      title: 'Rendez-vous par praticien',
      emptyLabel: 'Aucun RDV sur la période.',
      isEmpty: groups.isEmpty,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              group.practitionerDisplayName ?? 'Praticien',
              style: textTheme.labelLarge,
            ),
          ),
          for (final appt in group.appointments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${appt.patientDisplayName} — '
                '${appt.motif ?? 'Sans motif'}',
                style: textTheme.bodyMedium,
              ),
            ),
        ],
      ],
    );
  }
}

class _NewPatientsSection extends StatelessWidget {
  const _NewPatientsSection({required this.patients});
  final List<BriefNewPatient> patients;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: const Key('cabinet_brief_new_patients_section'),
      title: 'Patients nouveaux',
      emptyLabel: 'Aucun nouveau patient sur la période.',
      isEmpty: patients.isEmpty,
      children: [
        for (final patient in patients)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(patient.patientDisplayName),
          ),
      ],
    );
  }
}

class _PlannedActsSection extends StatelessWidget {
  const _PlannedActsSection({required this.acts});
  final List<BriefPlannedAct> acts;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: const Key('cabinet_brief_planned_acts_section'),
      title: 'Actes prévus',
      emptyLabel: 'Aucun acte renseigné sur la période.',
      isEmpty: acts.isEmpty,
      children: [
        for (final act in acts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${act.count} × ${act.motif}'),
          ),
      ],
    );
  }
}

class _ProsthesesSection extends StatelessWidget {
  const _ProsthesesSection({required this.prostheses});
  final List<BriefProsthesis> prostheses;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: const Key('cabinet_brief_prostheses_section'),
      title: 'Prothèses à poser',
      emptyLabel: 'Aucune prothèse à poser sur la période.',
      isEmpty: prostheses.isEmpty,
      children: [
        for (final prosthesis in prostheses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${prosthesis.patientDisplayName} — '
              '${prosthesis.labName} (${prosthesis.status})',
            ),
          ),
      ],
    );
  }
}

class _OpenTasksSection extends StatelessWidget {
  const _OpenTasksSection({required this.tasks});
  final List<BriefOpenTask> tasks;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: const Key('cabinet_brief_open_tasks_section'),
      title: 'Tâches ouvertes',
      emptyLabel: 'Aucune tâche ouverte.',
      isEmpty: tasks.isEmpty,
      children: [
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${task.title} '
              '(assigné : ${task.assigneeDisplayName ?? 'non assigné'})',
            ),
          ),
      ],
    );
  }
}

class _CabinetBriefSkeleton extends StatelessWidget {
  const _CabinetBriefSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 4; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: NubiaSkeletonLoader(height: 88, borderRadius: 12),
          ),
      ],
    );
  }
}
