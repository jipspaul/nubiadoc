import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

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
    return BlocConsumer<PatientFicheBloc, PatientFicheState>(
      listenWhen: (prev, curr) =>
          (prev.pdfBytes == null && curr.pdfBytes != null) ||
          (prev.exportPdfError == null && curr.exportPdfError != null),
      listener: (context, state) async {
        if (state.pdfBytes != null) {
          final box = context.findRenderObject() as RenderBox?;
          final origin =
              box == null ? null : box.localToGlobal(Offset.zero) & box.size;
          await Share.shareXFiles(
            [
              XFile.fromData(
                state.pdfBytes!,
                name: state.pdfFilename ?? 'fiche_patient.pdf',
                mimeType: 'application/pdf',
              ),
            ],
            subject: 'Fiche ${patient.fullName}',
            sharePositionOrigin: origin,
          );
        }
        if (state.exportPdfError != null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.exportPdfError!)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(patient.fullName),
            actions: [
              if (state.isExportingPdf)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  key: const Key('export_pdf_button'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Exporter PDF',
                  onPressed: () => context
                      .read<PatientFicheBloc>()
                      .add(ExportPdfRequested(patient)),
                ),
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
                const SizedBox(height: 16),
                PatientTagsSection(patientId: patient.id),
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
    final cs = Theme.of(context).colorScheme;
    return NubiaCard(
      key: const Key('clinical_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_information_outlined,
                  size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Notes cliniques',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          if (patient.birthDate != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.cake_outlined, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Text(
                  _formatDate(patient.birthDate!),
                  key: const Key('clinical_birth_date'),
                ),
              ],
            ),
          ],
          if (patient.lastVisitAt != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.history_outlined,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Text(
                  'Dernière visite : ${_formatDate(patient.lastVisitAt!)}',
                  key: const Key('clinical_last_visit'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

/// Étiquettes administratives du patient (#4041) — chargement, ajout,
/// suppression. Distinct du journal clinique : zéro donnée de santé.
class PatientTagsSection extends StatefulWidget {
  const PatientTagsSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientTagsSection> createState() => _PatientTagsSectionState();
}

class _PatientTagsSectionState extends State<PatientTagsSection> {
  List<PatientTag>? _tags;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await GetIt.instance<ListPatientTagsUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (tags) => setState(() {
        _tags = tags;
        _error = null;
      }),
    );
  }

  Future<void> _addTag(String label) async {
    setState(() => _submitting = true);
    final result = await GetIt.instance<CreatePatientTagUseCase>()(
      widget.patientId,
      label: label,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _load(),
    );
  }

  Future<void> _removeTag(String tagId) async {
    final result = await GetIt.instance<DeletePatientTagUseCase>()(
      widget.patientId,
      tagId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _load(),
    );
  }

  Future<void> _openAddDialog() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle étiquette'),
        content: NubiaTextField(
          key: const Key('patient_tag_label_field'),
          controller: controller,
          label: 'Libellé',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('patient_tag_dialog_confirm'),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) {
      await _addTag(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tags = _tags;

    return NubiaCard(
      key: const Key('patient_tags_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.label_outline, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('Étiquettes', style: textTheme.titleMedium),
              const Spacer(),
              IconButton(
                key: const Key('patient_tags_add_button'),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                tooltip: 'Ajouter une étiquette',
                onPressed: _submitting ? null : _openAddDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: TextStyle(color: cs.error))
          else if (tags == null)
            const NubiaSkeletonLoader(height: 32, borderRadius: 16)
          else if (tags.isEmpty)
            Text(
              'Aucune étiquette.',
              key: const Key('patient_tags_empty'),
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Wrap(
              key: const Key('patient_tags_wrap'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  NubiaChip(
                    key: Key('patient_tag_${tag.id}'),
                    label: tag.label,
                    variant: NubiaChipVariant.input,
                    onRemove: () => _removeTag(tag.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
