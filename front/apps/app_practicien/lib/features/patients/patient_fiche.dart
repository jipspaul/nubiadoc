import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
          (prev.pdfFilePath == null && curr.pdfFilePath != null) ||
          (prev.exportPdfError == null && curr.exportPdfError != null),
      listener: (context, state) async {
        if (state.pdfFilePath != null) {
          final box = context.findRenderObject() as RenderBox?;
          final origin =
              box == null ? null : box.localToGlobal(Offset.zero) & box.size;
          await Share.shareXFiles(
            [XFile(state.pdfFilePath!, mimeType: 'application/pdf')],
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
