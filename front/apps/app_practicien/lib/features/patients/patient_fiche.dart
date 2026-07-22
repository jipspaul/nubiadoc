import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'medical_questionnaire_review_section.dart';
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

/// #4133 — deux onglets : Résumé (contenu historique inchangé) et
/// Documents (GED, #4042, désormais avec filtre catégorie + upload).
class _PatientFicheScaffold extends StatefulWidget {
  final CabinetPatient patient;
  const _PatientFicheScaffold({required this.patient});

  @override
  State<_PatientFicheScaffold> createState() => _PatientFicheScaffoldState();
}

class _PatientFicheScaffoldState extends State<_PatientFicheScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
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
            bottom: TabBar(
              key: const Key('patient_fiche_tabs'),
              controller: _tabController,
              tabs: const [
                Tab(text: 'Résumé'),
                Tab(text: 'Documents'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.showClinical) ClinicalSection(patient: patient),
                    const SizedBox(height: 16),
                    MedicalQuestionnaireReviewSection(patientId: patient.id),
                    const SizedBox(height: 16),
                    PatientTagsSection(patientId: patient.id),
                    const SizedBox(height: 16),
                    PatientOrthodonticsSection(patientId: patient.id),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: PatientDocumentsSection(patientId: patient.id),
              ),
            ],
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

/// Libellé français par valeur de `kind` (bague/contention/gouttiere,
/// `VALID_STEP_KINDS` côté back, `api/src/orthodontics.rs`).
const _kOrthodonticStepKinds = <(String, String)>[
  ('bague', 'Bague'),
  ('contention', 'Contention'),
  ('gouttiere', 'Gouttière'),
];

/// Suivi orthodontique (#4135/#4136) : étapes du premier traitement en
/// cours (`status = 'in_progress'`, sinon le premier traitement listé),
/// triées par `step_number`, avec ajout d'étape. La création d'un
/// traitement orthodontique lui-même n'est pas couverte par cette section
/// (hors scope de #4136, aucun écran de création demandé).
class PatientOrthodonticsSection extends StatefulWidget {
  const PatientOrthodonticsSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientOrthodonticsSection> createState() =>
      _PatientOrthodonticsSectionState();
}

class _PatientOrthodonticsSectionState
    extends State<PatientOrthodonticsSection> {
  List<OrthodonticTreatment>? _treatments;
  String? _error;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await GetIt.instance<ListOrthodonticTreatmentsUseCase>()(
      widget.patientId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (treatments) => setState(() {
        _treatments = treatments;
        _error = null;
      }),
    );
  }

  /// Le traitement affiché : le premier `in_progress`, sinon le premier de
  /// la liste (créé le plus tôt — l'API trie par `created_at ASC`).
  OrthodonticTreatment? get _activeTreatment {
    final treatments = _treatments;
    if (treatments == null || treatments.isEmpty) return null;
    return treatments.firstWhere(
      (t) => t.status == 'in_progress',
      orElse: () => treatments.first,
    );
  }

  Future<void> _addStep() async {
    final treatment = _activeTreatment;
    if (treatment == null) return;

    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Type d\'étape'),
            ),
            for (final (value, label) in _kOrthodonticStepKinds)
              ListTile(
                key: Key('ortho_step_kind_$value'),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, value),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    final nextStepNumber = treatment.steps.isEmpty
        ? 1
        : treatment.steps
                .map((s) => s.stepNumber)
                .reduce((a, b) => a > b ? a : b) +
            1;

    setState(() => _adding = true);
    final result = await GetIt.instance<AddOrthodonticStepUseCase>()(
      treatment.id,
      stepNumber: nextStepNumber,
      kind: kind,
    );
    if (!mounted) return;
    setState(() => _adding = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _load(),
    );
  }

  String _kindLabel(String kind) => _kOrthodonticStepKinds
      .firstWhere((e) => e.$1 == kind, orElse: () => (kind, kind))
      .$2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final treatments = _treatments;
    final treatment = _activeTreatment;

    return NubiaCard(
      key: const Key('patient_orthodontics_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.align_horizontal_center_outlined,
                  size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('Suivi orthodontique',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (treatment != null)
                IconButton(
                  key: const Key('patient_orthodontics_add_step_button'),
                  icon: _adding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  tooltip: 'Ajouter une étape',
                  onPressed: _adding ? null : _addStep,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: TextStyle(color: cs.error))
          else if (treatments == null)
            const NubiaSkeletonLoader(height: 48, borderRadius: 8)
          else if (treatment == null)
            Text(
              'Aucun traitement orthodontique en cours.',
              key: const Key('patient_orthodontics_empty'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Column(
              key: const Key('patient_orthodontics_steps_list'),
              children: [
                // Trié défensivement ici plutôt que de dépendre uniquement
                // de l'ordre déjà correct renvoyé par l'API (ORDER BY
                // step_number, api/src/orthodontics.rs) — l'entité elle-même
                // ne garantit pas cet ordre (ex. construite directement en
                // test, ou après une future mutation en mémoire).
                for (final step in [
                  ...treatment.steps
                ]..sort((a, b) => a.stepNumber.compareTo(b.stepNumber)))
                  ListRow(
                    key: Key('ortho_step_${step.id}'),
                    leading: Icon(Icons.circle_outlined, color: cs.primary),
                    title: '${step.stepNumber}. ${_kindLabel(step.kind)}',
                    subtitle: step.conformityNotes,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Catégories acceptées par l'API (`VALID_CATEGORIES`, `api/src/clinical.rs`)
/// — libellé français + icône, mêmes valeurs brutes que `PatientDocument.category`
/// (pas le `DocumentCategory` du coffre-fort patient, dont le mapping diffère).
const _kDocumentCategories = <(String, String, IconData)>[
  ('devis', 'Devis', Icons.request_quote_outlined),
  ('facture', 'Facture', Icons.receipt_long_outlined),
  ('ordonnance', 'Ordonnance', Icons.medication_outlined),
  ('radio', 'Radio', Icons.image_outlined),
  ('cbct', 'CBCT', Icons.view_in_ar_outlined),
  ('photo', 'Photo', Icons.photo_camera_outlined),
  ('cr', 'Compte-rendu', Icons.description_outlined),
  ('consigne', 'Consigne', Icons.assignment_outlined),
  ('attestation', 'Attestation', Icons.verified_outlined),
  ('carte_mutuelle', 'Carte mutuelle', Icons.badge_outlined),
  ('passeport_implantaire', 'Passeport implantaire', Icons.badge_outlined),
  ('consentement', 'Consentement', Icons.verified_user_outlined),
];

/// Documents du dossier patient (GED, §4.4, #4042/#4133) — liste filtrable
/// par catégorie + upload. `POST .../documents` (#4133) câblé ; la
/// prévisualisation/téléchargement du contenu (ex. image radio) reste hors
/// scope : aucune route backend ne sert le contenu d'un document côté
/// cabinet aujourd'hui (`GET /v1/documents/:id/download` est réservé au
/// patient lui-même) — signalé séparément (#4286).
class PatientDocumentsSection extends StatefulWidget {
  const PatientDocumentsSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientDocumentsSection> createState() =>
      _PatientDocumentsSectionState();
}

class _PatientDocumentsSectionState extends State<PatientDocumentsSection> {
  List<PatientDocument>? _documents;
  String? _error;
  String? _categoryFilter;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await GetIt.instance<ListPatientDocumentsUseCase>()(
      widget.patientId,
      category: _categoryFilter,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (documents) => setState(() {
        _documents = documents;
        _error = null;
      }),
    );
  }

  void _setFilter(String? category) {
    setState(() {
      _categoryFilter = category;
      _documents = null;
    });
    _load();
  }

  Future<void> _pickAndUpload() async {
    final file = await GetIt.instance<FilePickerService>().pickFile();
    if (file == null || !mounted) return;

    final category = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Type de document'),
              ),
              for (final (value, label, icon) in _kDocumentCategories)
                ListTile(
                  key: Key('upload_cat_$value'),
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () => Navigator.pop(ctx, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (category == null || !mounted) return;

    setState(() => _uploading = true);
    final result = await GetIt.instance<UploadPatientDocumentUseCase>()(
      widget.patientId,
      bytes: file.bytes,
      filename: file.name,
      mimeType: file.mimeType,
      category: category,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => _load(),
    );
  }

  IconData _iconFor(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} Ko';
    return '${(kb / 1024).toStringAsFixed(1)} Mo';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final documents = _documents;

    return NubiaCard(
      key: const Key('patient_documents_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('Documents', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                key: const Key('patient_documents_upload_button'),
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                tooltip: 'Envoyer un document',
                onPressed: _uploading ? null : _pickAndUpload,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              key: const Key('patient_documents_filters'),
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: const Key('patient_documents_filter_all'),
                    label: const Text('Tous'),
                    selected: _categoryFilter == null,
                    onSelected: (_) => _setFilter(null),
                  ),
                ),
                for (final (value, label, _) in _kDocumentCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('patient_documents_filter_$value'),
                      label: Text(label),
                      selected: _categoryFilter == value,
                      onSelected: (_) => _setFilter(value),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: TextStyle(color: cs.error))
          else if (documents == null)
            const NubiaSkeletonLoader(height: 48, borderRadius: 8)
          else if (documents.isEmpty)
            Text(
              'Aucun document.',
              key: const Key('patient_documents_empty'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else
            Column(
              key: const Key('patient_documents_list'),
              children: [
                for (final doc in documents)
                  ListRow(
                    key: Key('patient_document_${doc.id}'),
                    leading: Icon(_iconFor(doc.mimeType), color: cs.primary),
                    title: doc.filename,
                    subtitle: '${doc.category} · ${_formatSize(doc.sizeBytes)}',
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
