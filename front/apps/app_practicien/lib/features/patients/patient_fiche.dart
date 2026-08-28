import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import 'async_section_state.dart';
import 'patient_fiche_bloc.dart';
import 'patient_journal_section.dart';

class PatientFiche extends StatelessWidget {
  final CabinetPatient patient;

  /// Callbacks d'action de l'en-tête (#4985, maquette design-v2 §.hb) —
  /// `PatientFiche` n'est référencée par aucune route à ce jour (cf.
  /// `patients_page.dart`), donc sans cible de navigation établie pour
  /// « Nouveau devis »/« Démarrer une consultation ». Laissés au caller
  /// plutôt que fabriqués : bouton désactivé (comportement `NubiaButton`
  /// standard) tant qu'aucun callback n'est fourni.
  final VoidCallback? onNewQuote;
  final VoidCallback? onStartConsultation;

  const PatientFiche({
    super.key,
    required this.patient,
    this.onNewQuote,
    this.onStartConsultation,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PatientFicheBloc(),
      child: _PatientFicheScaffold(
        patient: patient,
        onNewQuote: onNewQuote,
        onStartConsultation: onStartConsultation,
      ),
    );
  }
}

/// #4133 — deux onglets : Résumé (contenu historique inchangé) et
/// Documents (GED, #4042, désormais avec filtre catégorie + upload).
class _PatientFicheScaffold extends StatefulWidget {
  final CabinetPatient patient;
  final VoidCallback? onNewQuote;
  final VoidCallback? onStartConsultation;

  const _PatientFicheScaffold({
    required this.patient,
    this.onNewQuote,
    this.onStartConsultation,
  });

  @override
  State<_PatientFicheScaffold> createState() => _PatientFicheScaffoldState();
}

class _PatientFicheScaffoldState extends State<_PatientFicheScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Alertes cliniques du dossier (allergies + traitements à risque, #4974)
  /// — même source et même entité que `ClinicalSession.medicalAlerts` côté
  /// consultation au fauteuil (#4936). Chargées à part de `PatientFicheBloc`
  /// (affichage passif d'en-tête, indépendant de l'onglet actif) ; une
  /// erreur de chargement laisse simplement l'en-tête sans pastille plutôt
  /// que de bloquer l'affichage de la fiche.
  List<MedicalAlert> _medicalAlerts = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMedicalAlerts();
  }

  Future<void> _loadMedicalAlerts() async {
    final result =
        await GetIt.instance<GetMedicalRecordUseCase>()(widget.patient.id);
    if (!mounted) return;
    result.fold(
      (_) {},
      (record) => setState(() => _medicalAlerts = record.medicalAlerts),
    );
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
          final filename = state.pdfFilename ?? 'fiche_patient.pdf';
          if (isDesktopPlatform) {
            // Desktop : la feuille de partage système (`Share.shareXFiles`)
            // n'est pas implémentée sur Linux et n'a de sens qu'en présence
            // d'apps de partage tierces sur Windows/macOS — on attend un
            // téléchargement/enregistrement classique à la place.
            await GetIt.instance<FilePickerService>().saveFile(
              bytes: state.pdfBytes!,
              fileName: filename,
            );
          } else {
            final box = context.findRenderObject() as RenderBox?;
            final origin = box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size;
            await Share.shareXFiles(
              [
                XFile.fromData(
                  state.pdfBytes!,
                  name: filename,
                  mimeType: 'application/pdf',
                ),
              ],
              subject: 'Fiche ${patient.fullName}',
              sharePositionOrigin: origin,
            );
          }
        }
        if (state.exportPdfError != null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.exportPdfError!)),
          );
        }
      },
      builder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final tokens = Theme.of(context).extension<NubiaTokens>()!;

        return Scaffold(
          // #4985, maquette design-v2 §.hd/.hb — en-tête identité (retour,
          // avatar à initiales, nom, sous-titre) + barre d'actions, en lieu
          // et place de l'`AppBar` à titre seul. `Container`+`TabBar` plutôt
          // qu'`AppBar.title`/`actions` : la maquette demande un en-tête à
          // deux lignes (nom, sous-titre) et trois boutons libellés, hors du
          // gabarit standard d'une AppBar (même convention que
          // `PatientHeaderBar`, #5024).
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(172),
            child: Column(
              children: [
                Container(
                  key: const Key('patient_fiche_header'),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border:
                        Border(bottom: BorderSide(color: tokens.borderSubtle)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('patient_fiche_back_button'),
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                      NubiaAvatar(
                        key: const Key('patient_fiche_avatar'),
                        initials: initialsFrom(patient.fullName),
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // #4974 — pastilles d'alerte clinique à côté du
                            // nom, visibles quel que soit l'onglet actif
                            // (en-tête, pas dans un onglet) ; `Wrap` plutôt
                            // que `Row` pour refluer si le nombre d'alertes
                            // dépasse la largeur disponible, même convention
                            // que `PatientIdentityBar` (#4957).
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  patient.fullName,
                                  key: const Key('patient_fiche_name'),
                                  style: textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                for (final alert in _medicalAlerts)
                                  StatusPill(
                                    key: Key(
                                        'patient_fiche_alert_pill_${alert.kind}_${alert.label}'),
                                    label: _clinicalAlertLabel(alert),
                                    variant: alert.kind == 'allergie'
                                        ? StatusPillVariant.error
                                        : StatusPillVariant.warning,
                                    icon: alert.kind == 'allergie'
                                        ? Icons.warning
                                        : null,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _patientSubtitle(patient),
                              key: const Key('patient_fiche_subtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Défile horizontalement plutôt que de contraindre
                      // dans le `Row` parent : trois boutons libellés +
                      // toggle ne tiennent pas toujours dans la largeur
                      // disponible (ex. surface de test étroite) — préférer
                      // un défilement discret à un débordement `RenderFlex`.
                      // `Expanded` (plutôt qu'un enfant nu) : borne la
                      // largeur du scroll view, sinon il se dimensionne à
                      // la largeur naturelle de son contenu et déborde
                      // quand même du `Row` parent.
                      Expanded(
                        flex: 2,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (state.isExportingPdf)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              else
                                NubiaButton(
                                  key: const Key('export_pdf_button'),
                                  label: 'Exporter',
                                  icon: Icons.picture_as_pdf_outlined,
                                  variant: NubiaButtonVariant.secondary,
                                  size: NubiaButtonSize.sm,
                                  onPressed: () => context
                                      .read<PatientFicheBloc>()
                                      .add(ExportPdfRequested(patient)),
                                ),
                              const SizedBox(width: 8),
                              NubiaButton(
                                key:
                                    const Key('patient_fiche_new_quote_button'),
                                label: 'Nouveau devis',
                                icon: Icons.description_outlined,
                                variant: NubiaButtonVariant.secondary,
                                size: NubiaButtonSize.sm,
                                onPressed: widget.onNewQuote,
                              ),
                              const SizedBox(width: 8),
                              NubiaButton(
                                key: const Key(
                                    'patient_fiche_start_consultation_button'),
                                label: 'Démarrer une consultation',
                                icon: Icons.medical_services_outlined,
                                variant: NubiaButtonVariant.primary,
                                size: NubiaButtonSize.sm,
                                onPressed: widget.onStartConsultation,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Hors du cluster défilant : toujours atteignable sans
                      // scroll (le bouton le plus ancien de l'en-tête, cf.
                      // `patient_fiche_clinical_toggle_test.dart`).
                      IconButton(
                        key: const Key('toggle_clinical'),
                        icon: Icon(
                          state.showClinical
                              ? Icons.visibility_off
                              : Icons.visibility,
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
                ),
                TabBar(
                  key: const Key('patient_fiche_tabs'),
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Résumé'),
                    Tab(text: 'Documents'),
                  ],
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PatientJournalSection(patientId: patient.id),
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

/// Desktop natif (Windows/Linux/macOS) : `Share.shareXFiles` (#4983) n'y
/// est pas cohérent (non implémenté sur Linux, feuille de partage système
/// hors sujet sans app tierce sur Windows/macOS) — un export y déclenche un
/// téléchargement/enregistrement classique à la place. Le web garde la
/// feuille de partage : `defaultTargetPlatform` y reflète le device
/// simulé (souvent mobile/tablette), pas l'OS hôte réel.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Libellé de pastille d'alerte clinique (#4974) — même convention que
/// `PatientIdentityBar._clinicalAlertLabel` / `PatientAlertsBox._labelFor`
/// (préfixe « Allergie » pour `kind == 'allergie'`, libellé brut sinon).
String _clinicalAlertLabel(MedicalAlert alert) =>
    alert.kind == 'allergie' ? 'Allergie ${alert.label}' : alert.label;

/// Date JJ/MM/AAAA (heure locale) — format imposé par la maquette design-v2,
/// partagé par l'en-tête et `ClinicalSection`.
String _formatDate(DateTime d) {
  final local = d.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}

/// Âge en années révolues à partir d'une date de naissance (heure locale) —
/// même calcul que `PatientIdentityBar._age` (consultation_clinique).
int _ageInYears(DateTime birthDate) {
  final now = DateTime.now();
  final d = birthDate.toLocal();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
    age--;
  }
  return age;
}

/// Sous-titre d'en-tête (#4985, maquette design-v2 §.sb) : âge · date de
/// naissance · ancienneté · dernière visite — champs absents (naissance
/// inconnue, jamais venu) omis proprement plutôt que fabriqués.
String _patientSubtitle(CabinetPatient patient) {
  final birthDate = patient.birthDate;
  final lastVisit = patient.lastVisitAt;
  final parts = <String>[
    if (birthDate != null) '${_ageInYears(birthDate)} ans',
    if (birthDate != null) 'né(e) le ${_formatDate(birthDate)}',
    'patient(e) depuis ${patient.createdAt.toLocal().year}',
    if (lastVisit != null) 'dernière visite le ${_formatDate(lastVisit)}',
  ];
  return parts.join(' · ');
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
}

/// Étiquettes administratives du patient (#4041) — chargement, ajout,
/// suppression. Distinct du journal clinique : zéro donnée de santé.
class PatientTagsSection extends StatefulWidget {
  const PatientTagsSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientTagsSection> createState() => _PatientTagsSectionState();
}

class _PatientTagsSectionState extends State<PatientTagsSection>
    with AsyncSectionState<List<PatientTag>, PatientTagsSection> {
  bool _submitting = false;

  @override
  Future<Either<Failure, List<PatientTag>>> fetchSection() =>
      GetIt.instance<ListPatientTagsUseCase>()(widget.patientId);

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
      (_) => loadSection(),
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
      (_) => loadSection(),
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
    final tags = data;

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
          if (error != null)
            NubiaErrorWidget(message: error!, onRetry: loadSection)
          else if (loading || tags == null)
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

class _PatientOrthodonticsSectionState extends State<PatientOrthodonticsSection>
    with
        AsyncSectionState<List<OrthodonticTreatment>,
            PatientOrthodonticsSection> {
  bool _adding = false;
  bool _pickingKind = false;

  @override
  Future<Either<Failure, List<OrthodonticTreatment>>> fetchSection() =>
      GetIt.instance<ListOrthodonticTreatmentsUseCase>()(widget.patientId);

  /// Le traitement affiché : le premier `in_progress`, sinon le premier de
  /// la liste (créé le plus tôt — l'API trie par `created_at ASC`).
  OrthodonticTreatment? get _activeTreatment {
    final treatments = data;
    if (treatments == null || treatments.isEmpty) return null;
    return treatments.firstWhere(
      (t) => t.status == 'in_progress',
      orElse: () => treatments.first,
    );
  }

  void _startAddStep() => setState(() => _pickingKind = true);

  void _cancelAddStep() => setState(() => _pickingKind = false);

  Future<void> _addStep(String kind) async {
    final treatment = _activeTreatment;
    if (treatment == null) return;

    final nextStepNumber = treatment.steps.isEmpty
        ? 1
        : treatment.steps
                .map((s) => s.stepNumber)
                .reduce((a, b) => a > b ? a : b) +
            1;

    setState(() {
      _adding = true;
      _pickingKind = false;
    });
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
      (_) => loadSection(),
    );
  }

  String _kindLabel(String kind) => _kOrthodonticStepKinds
      .firstWhere((e) => e.$1 == kind, orElse: () => (kind, kind))
      .$2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final treatments = data;
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
                  onPressed:
                      (_adding || _pickingKind) ? null : _startAddStep,
                ),
            ],
          ),
          if (_pickingKind) ...[
            const SizedBox(height: 8),
            _OrthodonticStepKindPicker(
              key: const Key('patient_orthodontics_kind_picker'),
              busy: _adding,
              onSelect: _addStep,
              onCancel: _adding ? null : _cancelAddStep,
            ),
          ],
          const SizedBox(height: 8),
          if (error != null)
            NubiaErrorWidget(message: error!, onRetry: loadSection)
          else if (loading || treatments == null)
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

/// Choix du type d'étape ortho (#4980, maquette design-v2 point 7) : sur
/// poste fixe, remplace le `showModalBottomSheet` par une sélection en
/// place, sous le bouton d'ajout — même convention que
/// `_DocumentCategoryPicker` (#4981). Les trois `kind` restent ceux de
/// [_kOrthodonticStepKinds].
class _OrthodonticStepKindPicker extends StatelessWidget {
  const _OrthodonticStepKindPicker({
    super.key,
    required this.busy,
    required this.onSelect,
    required this.onCancel,
  });

  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.borderSubtle.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Type d'étape",
                  style: textTheme.labelLarge,
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  key: const Key('patient_orthodontics_kind_cancel'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Annuler',
                  onPressed: onCancel,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _kOrthodonticStepKinds)
                NubiaChip(
                  key: Key('ortho_step_kind_$value'),
                  label: label,
                  variant: NubiaChipVariant.choice,
                  onTap: busy ? null : () => onSelect(value),
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

class _PatientDocumentsSectionState extends State<PatientDocumentsSection>
    with AsyncSectionState<List<PatientDocument>, PatientDocumentsSection> {
  String? _categoryFilter;
  bool _uploading = false;
  PickedFile? _pendingFile;

  @override
  Future<Either<Failure, List<PatientDocument>>> fetchSection() =>
      GetIt.instance<ListPatientDocumentsUseCase>()(
        widget.patientId,
        category: _categoryFilter,
      );

  void _setFilter(String? category) {
    setState(() => _categoryFilter = category);
    loadSection();
  }

  Future<void> _pickFile() async {
    final file = await GetIt.instance<FilePickerService>().pickFile();
    if (file == null || !mounted) return;
    setState(() => _pendingFile = file);
  }

  void _cancelPending() => setState(() => _pendingFile = null);

  Future<void> _selectCategoryAndUpload(String category) async {
    final file = _pendingFile;
    if (file == null) return;

    setState(() => _uploading = true);
    final result = await GetIt.instance<UploadPatientDocumentUseCase>()(
      widget.patientId,
      bytes: file.bytes,
      filename: file.name,
      mimeType: file.mimeType,
      category: category,
    );
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _pendingFile = null;
    });
    result.fold(
      (failure) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => loadSection(),
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
    final documents = data;

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
                onPressed:
                    (_uploading || _pendingFile != null) ? null : _pickFile,
              ),
            ],
          ),
          if (_pendingFile != null) ...[
            const SizedBox(height: 8),
            _DocumentCategoryPicker(
              key: const Key('patient_documents_category_picker'),
              fileName: _pendingFile!.name,
              busy: _uploading,
              onSelect: _selectCategoryAndUpload,
              onCancel: _uploading ? null : _cancelPending,
            ),
          ],
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
          if (error != null)
            NubiaErrorWidget(message: error!, onRetry: loadSection)
          else if (loading || documents == null)
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
                    trailing: Icon(
                      Icons.lock_outline,
                      color: cs.onSurfaceVariant,
                      semanticLabel: 'Lecture indisponible depuis le cabinet',
                    ),
                  ),
              ],
            ),
          if (documents != null && documents.isNotEmpty) ...[
            const SizedBox(height: 8),
            const _DocumentsReadOnlyNotice(
              key: Key('patient_documents_ged_notice'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Choix de la catégorie à l'upload d'un document (#4981, maquette design-v2
/// point 7) : sur poste fixe, remplace le `showModalBottomSheet` à 75 % de
/// hauteur par une sélection en place, sous le bouton d'upload. Les 12
/// catégories restent celles de [_kDocumentCategories] (valeurs brutes API).
class _DocumentCategoryPicker extends StatelessWidget {
  const _DocumentCategoryPicker({
    super.key,
    required this.fileName,
    required this.busy,
    required this.onSelect,
    required this.onCancel,
  });

  final String fileName;
  final bool busy;
  final ValueChanged<String> onSelect;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.borderSubtle.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Type de document — $fileName',
                  style: textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  key: const Key('patient_documents_category_cancel'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Annuler',
                  onPressed: onCancel,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label, icon) in _kDocumentCategories)
                NubiaChip(
                  key: Key('upload_cat_$value'),
                  label: label,
                  icon: icon,
                  variant: NubiaChipVariant.choice,
                  onTap: busy ? null : () => onSelect(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bandeau info (#4286) : aucune route backend ne sert le contenu d'un
/// document côté cabinet (`GET /v1/documents/:id/download` réservé au
/// patient) — la liste ne doit pas ressembler à des éléments cliquables,
/// donc on l'énonce en clair en plus du cadenas sur chaque ligne.
class _DocumentsReadOnlyNotice extends StatelessWidget {
  const _DocumentsReadOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: tokens.infoFg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Aucun document n'est consultable depuis le cabinet (#4286) : "
              'le back ne sert le contenu qu\'au patient lui-même. Les '
              "documents s'envoient et se listent, mais ne s'ouvrent pas — "
              "l'icône le dit.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.infoFg,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
