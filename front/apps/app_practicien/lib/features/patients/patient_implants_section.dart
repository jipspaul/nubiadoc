import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Passeport implantaire côté fiche patient praticien (#4140/#4141).
///
/// Extrait dans un fichier dédié plutôt qu'ajouté à `patient_fiche.dart`
/// (déjà au plafond absolu CLAUDE.md, 700+ lignes — refactor requis avant
/// tout nouvel ajout, cf. `PatientTagsSection`/`PatientOrthodonticsSection`
/// déjà présentes dans ce fichier). `POST /v1/cabinet/patients/:id/implants`
/// ne renvoie que l'id créé (pas les champs) : la liste affichée ici est
/// reconstruite localement à partir des soumissions de la session — aucune
/// route `GET` cabinet-scoped par patient n'existe pour lister les implants
/// déjà posés (seul `GET /v1/implant-passport`, côté compte patient, existe).
class PatientImplantsSection extends StatefulWidget {
  const PatientImplantsSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientImplantsSection> createState() => _PatientImplantsSectionState();
}

class _PatientImplantsSectionState extends State<PatientImplantsSection> {
  final List<ImplantItem> _implants = [];
  bool _submitting = false;

  Future<void> _openAddDialog() async {
    final brandController = TextEditingController();
    final refController = TextEditingController();
    final lotController = TextEditingController();
    final dateController = TextEditingController();
    final toothController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvel implant'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NubiaTextField(
                key: const Key('implant_brand_field'),
                controller: brandController,
                label: 'Marque',
              ),
              const SizedBox(height: 8),
              NubiaTextField(
                key: const Key('implant_ref_field'),
                controller: refController,
                label: 'Référence',
              ),
              const SizedBox(height: 8),
              NubiaTextField(
                key: const Key('implant_lot_field'),
                controller: lotController,
                label: 'Lot (optionnel)',
              ),
              const SizedBox(height: 8),
              NubiaTextField(
                key: const Key('implant_date_field'),
                controller: dateController,
                label: 'Date de pose AAAA-MM-JJ (optionnel)',
              ),
              const SizedBox(height: 8),
              NubiaTextField(
                key: const Key('implant_tooth_field'),
                controller: toothController,
                label: 'Position FDI (optionnel)',
              ),
              const SizedBox(height: 8),
              NubiaTextField(
                key: const Key('implant_notes_field'),
                controller: notesController,
                label: 'Notes (optionnel)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('patient_implant_dialog_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final brand = brandController.text.trim();
    final implantRef = refController.text.trim();
    if (brand.isEmpty || implantRef.isEmpty) return;

    setState(() => _submitting = true);
    final result = await GetIt.instance<CreateImplantUseCase>()(
      patientId: widget.patientId,
      brand: brand,
      implantRef: implantRef,
      lotNumber:
          lotController.text.trim().isEmpty ? null : lotController.text.trim(),
      placementDate: dateController.text.trim().isEmpty
          ? null
          : dateController.text.trim(),
      toothPosition: toothController.text.trim().isEmpty
          ? null
          : toothController.text.trim(),
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (implant) => setState(() => _implants.add(implant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return NubiaCard(
      key: const Key('patient_implants_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hardware_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('Passeport implantaire', style: textTheme.titleMedium),
              const Spacer(),
              IconButton(
                key: const Key('patient_implants_add_button'),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                tooltip: 'Ajouter un implant',
                onPressed: _submitting ? null : _openAddDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_implants.isEmpty)
            Text(
              'Aucun implant enregistré cette session.',
              key: const Key('patient_implants_empty'),
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Column(
              key: const Key('patient_implants_list'),
              children: [
                for (final implant in _implants)
                  ListRow(
                    key: Key('patient_implant_${implant.id}'),
                    leading: Icon(Icons.hardware_outlined, color: cs.primary),
                    title: implant.brand,
                    subtitle: () {
                      final parts = [
                        if (implant.toothPosition != null)
                          'Dent ${implant.toothPosition}',
                        if (implant.placementDate != null)
                          implant.placementDate!,
                      ];
                      return parts.isEmpty ? null : parts.join(' — ');
                    }(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
