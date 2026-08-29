import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/pro_auth_cubit.dart';
import 'send_to_pharmacy_cubit.dart';
import 'widgets/ordonnance_preview_sheet.dart';
import 'widgets/prescription_template_picker.dart';
import 'widgets/send_to_pharmacy_card.dart';
import 'ordonnances_bloc.dart';
import 'ordonnances_event.dart';
import 'ordonnances_state.dart';

/// Composition d'une nouvelle ordonnance (`/ordonnances/new?patientId=`).
/// Gated par [ProConfig.includeClinical] au niveau du router (route parente).
class OrdonnanceNewPage extends StatelessWidget {
  final String? patientId;

  const OrdonnanceNewPage({super.key, this.patientId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<OrdonnancesBloc>(),
      child: OrdonnanceNewBody(patientId: patientId),
    );
  }
}

// ---------------------------------------------------------------------------

class OrdonnanceNewBody extends StatefulWidget {
  const OrdonnanceNewBody({super.key, this.patientId});
  final String? patientId;

  @override
  State<OrdonnanceNewBody> createState() => _OrdonnanceNewBodyState();
}

class _OrdonnanceNewBodyState extends State<OrdonnanceNewBody> {
  late final SendToPharmacyCubit _pharmacyCubit;

  /// Vrai lorsque le bouton combiné a été tapé : consommé au prochain
  /// `OrdonnancesSigned` pour enchaîner l'envoi (#5000), sinon la
  /// signature reste une action isolée.
  bool _autoSendToPharmacy = false;

  @override
  void initState() {
    super.initState();
    _pharmacyCubit = GetIt.instance<SendToPharmacyCubit>();
  }

  @override
  void dispose() {
    _pharmacyCubit.close();
    super.dispose();
  }

  void _onSign(Prescription prescription) {
    _autoSendToPharmacy = false;
    context
        .read<OrdonnancesBloc>()
        .add(OrdonnancesSignRequested(prescription.id));
  }

  void _onSignAndSendToPharmacy(Prescription prescription) {
    _autoSendToPharmacy = true;
    context
        .read<OrdonnancesBloc>()
        .add(OrdonnancesSignRequested(prescription.id));
  }

  @override
  Widget build(BuildContext context) {
    final pid = widget.patientId;
    if (pid == null || pid.isEmpty) {
      return const NubiaEmptyState(
        key: Key('ordonnances_new'),
        icon: Icons.medication_outlined,
        title: 'Nouvelle ordonnance',
        subtitle: 'Ouvrez une fiche patient pour prescrire.',
      );
    }
    return BlocProvider<SendToPharmacyCubit>.value(
      value: _pharmacyCubit,
      child: BlocConsumer<OrdonnancesBloc, OrdonnancesState>(
        listener: (context, state) {
          if (state is OrdonnancesError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
          if (state is OrdonnancesSigned) {
            // La pharmacie déclarée n'est connue qu'une fois le patientId
            // disponible (post-signature ici) ; `send()` exige, lui, le
            // `prescription.id` — d'où l'enchaînement load() puis send().
            final autoSend = _autoSendToPharmacy;
            _autoSendToPharmacy = false;
            _pharmacyCubit.load(state.prescription.patientId).then((_) {
              if (autoSend) _pharmacyCubit.send(state.prescription.id);
            });
          }
        },
        builder: (context, state) {
          if (state is OrdonnancesSigned) {
            return _SignedConfirmation(prescription: state.prescription);
          }
          if (state is OrdonnancesCreated ||
              state is OrdonnancesSigningInProgress ||
              (state is OrdonnancesApplyingTemplate &&
                  state.prescription != null)) {
            final prescription = switch (state) {
              OrdonnancesCreated(:final prescription) => prescription,
              OrdonnancesSigningInProgress(:final prescription) => prescription,
              OrdonnancesApplyingTemplate(:final prescription) => prescription!,
              _ => throw StateError('unreachable'),
            };
            return _DraftReview(
              prescription: prescription,
              signing: state is OrdonnancesSigningInProgress,
              applyingTemplate: state is OrdonnancesApplyingTemplate,
              onSign: () => _onSign(prescription),
              onSignAndSendToPharmacy: () =>
                  _onSignAndSendToPharmacy(prescription),
            );
          }
          // Initial, Loading, Error, ApplyingTemplate sans brouillon (#4988,
          // modèle choisi avant création) : le formulaire reste monté pour
          // ne pas perdre la saisie (l'erreur est surfacée en snackbar).
          return _PrescriptionForm(
            patientId: pid,
            loading: state is OrdonnancesLoading,
            applyingTemplate: state is OrdonnancesApplyingTemplate,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Une ligne de médicament en cours de saisie.
///
/// Dose, fréquence et durée sont choisies en listes déroulantes (#4991,
/// maquette design-v2) plutôt que saisies en texte libre. La quantité n'est
/// pas non plus saisie librement (#4992) : elle se dérive de [dose],
/// [frequency] et [duration] via [calculatedQuantity]. [quantityOverride]
/// permet de la surcharger via l'action « Modifier » quand le calcul échoue
/// ou ne convient pas.
class _ItemDraft {
  final label = TextEditingController();

  /// Référence produit sélectionnée dans le référentiel médicament (#4989) —
  /// `null` tant qu'aucun résultat de recherche n'a été choisi, ou après un
  /// préremplissage par modèle (#4986, libellé seul, hors référentiel).
  MedicationReference? reference;

  String? dose;
  String? frequency;
  String? duration;
  final quantityOverride = TextEditingController();

  /// Fixe le médicament choisi dans le référentiel (#4989) : le libellé
  /// (DCI) ne se saisit plus librement, il provient de la sélection.
  void selectReference(MedicationReference selected) {
    reference = selected;
    label.text = selected.dci;
  }

  /// Réinitialise la sélection pour permettre de rechercher un autre
  /// médicament (#4989).
  void clearReference() {
    reference = null;
    label.text = '';
  }

  /// Vrai quand l'encart de calcul a été remplacé par la saisie manuelle
  /// (tap sur « Modifier ») — état UI porté par le draft pour survivre aux
  /// rebuilds de `_ItemCard` (StatelessWidget reconstruit à chaque `_refresh`).
  bool overridingQuantity = false;

  /// Posologie au format texte libre (« 1 comprimé, 3 fois / jour ») —
  /// combine [dose] et [frequency] pour rester compatible avec
  /// `PrescriptionItem.posology` (aperçu du document, calcul de quantité).
  String get posology =>
      (dose != null && frequency != null) ? '$dose, $frequency' : '';

  CalculatedQuantity? get calculatedQuantity =>
      computeQuantity(posology, duration ?? '');

  String? get effectiveQuantity {
    final override = quantityOverride.text.trim();
    if (override.isNotEmpty) return override;
    return calculatedQuantity?.label;
  }

  bool get isValid =>
      label.text.trim().isNotEmpty &&
      dose != null &&
      frequency != null &&
      duration != null &&
      (effectiveQuantity?.isNotEmpty ?? false);

  PrescriptionItem toItem() => PrescriptionItem(
        label: label.text.trim(),
        form: reference?.galenicForm,
        productReference: reference,
        posology: posology,
        duration: duration ?? '',
        quantity: effectiveQuantity ?? '',
      );

  void dispose() {
    label.dispose();
    quantityOverride.dispose();
  }
}

// ---------------------------------------------------------------------------
// Calcul de quantité (#4992) — dose × fréquence × durée.
// ---------------------------------------------------------------------------

/// Quantité dérivée de la posologie et de la durée (ex. « 15 comprimés »).
class CalculatedQuantity {
  const CalculatedQuantity({required this.count, required this.unit});

  final int count;
  final String unit;

  String get label => '$count $unit';
}

final _leadingNumber = RegExp(r'(\d+)');
final _explicitFrequency =
    RegExp(r'(\d+)\s*(?:fois|x)\s*(?:/|par)\s*jour', caseSensitive: false);
final _firstUnitWord = RegExp(r'\d+\s*([A-Za-zÀ-ÿ]+)');

/// Dérive dose × fréquence × durée à partir du texte libre de posologie
/// (« 1 comprimé, 3 fois par jour », « 1 comprimé matin et soir »…) et de
/// durée (« 5 jours »). Retourne `null` si l'un des trois facteurs ne peut
/// pas être extrait — la ligne reste alors invalide tant que la posologie et
/// la durée ne le permettent pas (ou que la quantité n'est pas surchargée).
CalculatedQuantity? computeQuantity(String posology, String duration) {
  final trimmedPosology = posology.trim();
  final doseMatch = _leadingNumber.firstMatch(trimmedPosology);
  if (doseMatch == null) return null;
  final dose = int.parse(doseMatch.group(1)!);

  final frequency = _frequencyFrom(trimmedPosology);
  if (frequency == null) return null;

  final durationMatch = _leadingNumber.firstMatch(duration.trim());
  if (durationMatch == null) return null;
  final days = int.parse(durationMatch.group(1)!);

  final count = dose * frequency * days;
  return CalculatedQuantity(
      count: count, unit: _unitFrom(trimmedPosology, count));
}

int? _frequencyFrom(String posology) {
  final explicit = _explicitFrequency.firstMatch(posology);
  if (explicit != null) return int.parse(explicit.group(1)!);
  final lower = posology.toLowerCase();
  final moments = ['matin', 'midi', 'soir']
      .where((moment) => lower.contains(moment))
      .length;
  return moments > 0 ? moments : null;
}

String _unitFrom(String posology, int count) {
  final match = _firstUnitWord.firstMatch(posology);
  var unit = match?.group(1)?.trim() ?? 'unité';
  if (count > 1 && !unit.endsWith('s')) unit = '${unit}s';
  return unit;
}

class _PrescriptionForm extends StatefulWidget {
  const _PrescriptionForm({
    required this.patientId,
    required this.loading,
    required this.applyingTemplate,
  });
  final String patientId;
  final bool loading;

  /// Modèle en cours d'application (#4988) : création implicite du
  /// brouillon + préremplissage des lignes, déclenchée par
  /// [use_template_button] avant toute création manuelle.
  final bool applyingTemplate;

  @override
  State<_PrescriptionForm> createState() => _PrescriptionFormState();
}

/// Seuil à partir duquel la composition et l'aperçu du document
/// s'affichent côte à côte (maquette design-v2, tablette cible 1258×834).
/// En dessous, la composition reste seule, pleine largeur.
const _kOrdonnanceSplitBreakpoint = 900.0;

/// Largeur du volet `.rgt` (aperçu) de la maquette design-v2.
const _kOrdonnancePreviewWidth = 458.0;

class _PrescriptionFormState extends State<_PrescriptionForm> {
  final List<_ItemDraft> _items = [_ItemDraft()];
  List<String> _allergies = const [];
  CabinetPatient? _patient;
  List<PrescriptionTemplate> _templates = const [];
  String? _selectedTemplateId;

  bool get _formValid => _items.isNotEmpty && _items.every((i) => i.isValid);

  @override
  void initState() {
    super.initState();
    _loadAllergies();
    _loadPatient();
    _loadTemplates();
  }

  /// #4986 (maquette design-v2) : les modèles sont proposés en tête du
  /// formulaire, avant toute saisie, plutôt qu'après création du brouillon
  /// (`_DraftReview`) — reprend `OrdonnancesBloc.loadTemplates()` (#4074),
  /// déjà utilisé par `PrescriptionTemplatePicker`.
  Future<void> _loadTemplates() async {
    final templates = await context.read<OrdonnancesBloc>().loadTemplates();
    if (!mounted) return;
    setState(() => _templates = templates);
  }

  /// Applique un modèle à la composition en cours : remplace les lignes
  /// saisies par celles du modèle (libellé seul — dose/fréquence/durée
  /// restent à choisir dans les listes déroulantes, comme pour un ajout via
  /// `_AddItemSearchField`).
  void _applyTemplate(PrescriptionTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      for (final item in _items) {
        item.dispose();
      }
      _items
        ..clear()
        ..addAll(template.items.isEmpty
            ? [_ItemDraft()]
            : template.items.map((i) => _ItemDraft()..label.text = i.label));
    });
  }

  /// Affichage passif uniquement (#4076, ADR-009 §8.6) : jamais de blocage
  /// ni de suggestion d'alternative — un échec de chargement laisse
  /// simplement le bandeau absent, la saisie n'est jamais impactée.
  Future<void> _loadAllergies() async {
    final result =
        await GetIt.instance<GetMedicalRecordUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (_) {},
      (record) => setState(() => _allergies = record.allergies),
    );
  }

  /// Identité patient (nom, âge, date de naissance) de l'en-tête (#4999,
  /// maquette design-v2 §.hd) — même use case que `PatientHeaderBar`
  /// (`treatment_plans`, #5024). Échec silencieux : l'en-tête retombe sur un
  /// nom générique plutôt que de bloquer la saisie de l'ordonnance.
  Future<void> _loadPatient() async {
    final result =
        await GetIt.instance<GetCabinetPatientUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (_) {},
      (patient) => setState(() => _patient = patient),
    );
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _submit() {
    context.read<OrdonnancesBloc>().add(
          OrdonnancesCreateRequested(
            patientId: widget.patientId,
            items: _items.map((i) => i.toItem()).toList(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final composition = SingleChildScrollView(
      key: const Key('ordonnance_form'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PatientIdentityHeader(patient: _patient),
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('use_template_button'),
            label: 'Utiliser un modèle',
            variant: NubiaButtonVariant.secondary,
            icon: Icons.description_outlined,
            isLoading: widget.applyingTemplate,
            onPressed: (widget.loading || widget.applyingTemplate)
                ? null
                : () async {
                    final bloc = context.read<OrdonnancesBloc>();
                    final template = await PrescriptionTemplatePicker.show(
                        context,
                        loadTemplates: bloc.loadTemplates);
                    if (template != null) {
                      bloc.add(OrdonnancesApplyTemplateRequested(
                        patientId: widget.patientId,
                        templateId: template.id,
                      ));
                    }
                  },
          ),
          const SizedBox(height: 20),
          _TemplateSection(
            templates: _templates,
            selectedTemplateId: _selectedTemplateId,
            onSelected: _applyTemplate,
          ),
          for (var i = 0; i < _items.length; i++) ...[
            _ItemCard(
              index: i,
              draft: _items[i],
              onChanged: _refresh,
              onRemove: _items.length == 1
                  ? null
                  : () => setState(() => _items.removeAt(i).dispose()),
            ),
            const SizedBox(height: 12),
          ],
          // Résolution de merge : main a remplacé le bouton « Ajouter un
          // médicament » par la recherche au référentiel DCI (#4989) — on garde
          // cette version. On y reporte la garde apportée par #4988 : pendant
          // l'application d'un modèle, on ne peut pas ajouter de ligne.
          _AddItemSearchField(
            enabled: !widget.loading && !widget.applyingTemplate,
            onSelected: (reference) => setState(
              () => _items.add(_ItemDraft()..selectReference(reference)),
            ),
          ),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('submit_ordonnance_button'),
            label: 'Créer l\'ordonnance',
            isLoading: widget.loading,
            onPressed:
                (!_formValid || widget.loading || widget.applyingTemplate)
                    ? null
                    : _submit,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_allergies.isNotEmpty) _AllergiesBanner(allergies: _allergies),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < _kOrdonnanceSplitBreakpoint) {
                return composition;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: composition),
                  SizedBox(
                    width: _kOrdonnancePreviewWidth,
                    child: OrdonnancePreviewSheet(
                      patient: _patient,
                      prescriberName: _prescriberName(context),
                      items: _items.map((i) => i.toItem()).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Section « Partir d'un modèle » (#4986, maquette design-v2) : cibles
/// tactiles affichées en tête de la composition, avant la saisie ligne à
/// ligne — remplace l'unique point d'entrée `use_template_button` de
/// `_DraftReview`, qui n'apparaissait qu'après création du brouillon (donc
/// après une saisie manuelle que le modèle aurait de toute façon effacée).
/// Vide (`templates` non chargés ou aucun modèle) : ne s'affiche pas.
class _TemplateSection extends StatelessWidget {
  const _TemplateSection({
    required this.templates,
    required this.selectedTemplateId,
    required this.onSelected,
  });

  final List<PrescriptionTemplate> templates;
  final String? selectedTemplateId;
  final ValueChanged<PrescriptionTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Padding(
      key: const Key('template_section'),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 20, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Partir d\'un modèle',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    NubiaBadge.count(count: templates.length),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final template in templates)
                      SizedBox(
                        width: 150,
                        child: _TemplateCard(
                          key: Key('template_card_${template.id}'),
                          template: template,
                          selected: template.id == selectedTemplateId,
                          onTap: () => onSelected(template),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: tokens.borderSubtle)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('ou',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: tokens.textTertiary)),
              ),
              Expanded(child: Divider(color: tokens.borderSubtle)),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Carte tactile d'un modèle (#4986) : libellé + origine (Cabinet/Standard,
/// `PrescriptionTemplate.isGlobal`, #4073) et nombre de lignes. État actif
/// (bordure/fond émeraude `brand600`/`brand50`) sur le modèle sélectionné —
/// même distinction cabinet/standard que `PrescriptionTemplatePicker`, sans
/// en changer la sémantique.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    super.key,
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PrescriptionTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final origin = template.isGlobal ? 'Standard' : 'Cabinet';
    final lineCount = template.items.length;
    final lines = lineCount > 1 ? '$lineCount lignes' : '$lineCount ligne';

    return Material(
      color: selected ? NubiaColors.brand50 : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? NubiaColors.brand600 : tokens.borderSubtle,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? NubiaColors.brand700
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$origin · $lines',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tokens.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Nom du prescripteur connecté (`ProAuthCubit`), utilisé à la fois par
/// l'en-tête d'identité patient (#4999) et par l'aperçu du document (#4997).
String? _prescriberName(BuildContext context) =>
    switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session.displayName,
      _ => null,
    };

// ---------------------------------------------------------------------------

/// En-tête d'identité patient (#4999, maquette design-v2 §.hd) : remplace le
/// titre anonyme « Médicaments à prescrire » — avatar aux initiales, nom du
/// patient, pastille « Brouillon » et sous-titre âge/date de naissance/
/// prescripteur. [patient] est `null` tant que `GetCabinetPatientUseCase`
/// n'a pas répondu (ou en cas d'échec, #4076 affichage passif) : l'en-tête
/// retombe alors sur un nom générique plutôt que de bloquer la saisie.
class _PatientIdentityHeader extends StatelessWidget {
  const _PatientIdentityHeader({required this.patient});

  final CabinetPatient? patient;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = patient != null && patient!.fullName.isNotEmpty
        ? patient!.fullName
        : 'Patient';
    final prescriberName = _prescriberName(context);
    final subtitle = _subtitle(prescriberName);

    return Row(
      key: const Key('ordonnance_patient_header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaAvatar(initials: initialsFrom(name), radius: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const StatusPill(
                    label: 'Brouillon',
                    variant: StatusPillVariant.info,
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String? _subtitle(String? prescriberName) {
    final birthDate = patient?.birthDate;
    final prescriber = prescriberName?.trim();
    final parts = <String>[
      if (birthDate != null) '${_age(birthDate)} ans',
      if (birthDate != null) 'né(e) le ${_formatBirthDate(birthDate)}',
      if (prescriber != null && prescriber.isNotEmpty)
        'suivi(e) par Dr $prescriber',
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}

/// Âge en années révolues à partir d'une date de naissance (heure locale) —
/// même calcul que `PatientIdentityBar._age` (consultation_clinique).
int _age(DateTime birthDate) {
  final now = DateTime.now();
  final d = birthDate.toLocal();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
    age--;
  }
  return age;
}

/// Date de naissance JJ/MM/AAAA (heure locale) — format imposé par la
/// maquette design-v2 (même convention que `PatientIdentityBar`).
String _formatBirthDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

// ---------------------------------------------------------------------------

/// Bandeau passif (#4076, ADR-009 §8.6) : affiche les allergies connues du
/// dossier médical. Jamais bloquant, ne désactive aucun champ, ne suggère
/// aucune alternative — hors périmètre MDR (dispositif médical exclu). La
/// mention à droite l'énonce à l'écran pour qu'aucune itération future ne le
/// « corrige » par erreur.
class _AllergiesBanner extends StatelessWidget {
  const _AllergiesBanner({required this.allergies});
  final List<String> allergies;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('allergies_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: tokens.warningBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning, size: 20, color: tokens.warningFg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allergies connues au dossier',
                  style: textTheme.labelLarge?.copyWith(
                    color: tokens.warningFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  allergies.join(' · '),
                  style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Affichage informatif. Aucune vérification automatique, '
              'aucune alternative suggérée — hors périmètre dispositif '
              'médical (ADR-009 §8.6).',
              style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Étiquette de classe thérapeutique (#4990, maquette design-v2 `.aci .tg`) :
/// rendue dans une teinte neutre unique, identique pour toutes les classes
/// (`NubiaTokens.neutralBg`/`neutralFg`, équivalent n100/n600). Ne prend
/// délibérément PAS les allergies du dossier en paramètre — les colorer
/// selon `_allergies` reviendrait à effectuer la vérification de
/// contre-indication que l'ADR-009 §8.6 exclut (#4076). Consommée par les
/// résultats de recherche référentiel DCI (#4989, `_MedicationSearchField`).
class TherapeuticClassLabel extends StatelessWidget {
  const TherapeuticClassLabel({super.key, required this.therapeuticClass});

  final String therapeuticClass;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: therapeuticClass,
      variant: StatusPillVariant.neutral,
    );
  }
}

// ---------------------------------------------------------------------------

/// Options de dose (#4991, maquette design-v2 `.fields`) — couvre les formes
/// galéniques les plus courantes (comprimé, sachet, bain de bouche…).
const _doseOptions = <NubiaSelectItem<String>>[
  NubiaSelectItem(value: '1 comprimé', label: '1 comprimé'),
  NubiaSelectItem(value: '2 comprimés', label: '2 comprimés'),
  NubiaSelectItem(value: '1 sachet', label: '1 sachet'),
  NubiaSelectItem(value: '1 ampoule', label: '1 ampoule'),
  NubiaSelectItem(value: '1 dose', label: '1 dose'),
  NubiaSelectItem(value: '1 application', label: '1 application'),
  NubiaSelectItem(value: '1 bain de bouche', label: '1 bain de bouche'),
  NubiaSelectItem(value: '5 ml', label: '5 ml'),
];

/// Options de fréquence quotidienne (#4991).
const _frequencyOptions = <NubiaSelectItem<String>>[
  NubiaSelectItem(value: '1 fois / jour', label: '1 fois / jour'),
  NubiaSelectItem(value: '2 fois / jour', label: '2 fois / jour'),
  NubiaSelectItem(value: '3 fois / jour', label: '3 fois / jour'),
  NubiaSelectItem(value: '4 fois / jour', label: '4 fois / jour'),
];

/// Options de durée de traitement (#4991).
const _durationOptions = <NubiaSelectItem<String>>[
  NubiaSelectItem(value: '3 jours', label: '3 jours'),
  NubiaSelectItem(value: '5 jours', label: '5 jours'),
  NubiaSelectItem(value: '7 jours', label: '7 jours'),
  NubiaSelectItem(value: '10 jours', label: '10 jours'),
  NubiaSelectItem(value: '14 jours', label: '14 jours'),
  NubiaSelectItem(value: '1 mois', label: '1 mois'),
];

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.index,
    required this.draft,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final _ItemDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      key: Key('item_card_$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Médicament ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              if (onRemove != null)
                IconButton(
                  key: Key('remove_item_$index'),
                  tooltip: 'Retirer',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _MedicationSearchField(
            index: index,
            draft: draft,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NubiaSelect<String>(
                  key: Key('item_${index}_posology'),
                  items: _doseOptions,
                  value: draft.dose,
                  label: 'Dose',
                  onChanged: (v) {
                    draft.dose = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NubiaSelect<String>(
                  key: Key('item_${index}_frequency'),
                  items: _frequencyOptions,
                  value: draft.frequency,
                  label: 'Fréquence',
                  onChanged: (v) {
                    draft.frequency = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NubiaSelect<String>(
                  key: Key('item_${index}_duration'),
                  items: _durationOptions,
                  value: draft.duration,
                  label: 'Durée',
                  onChanged: (v) {
                    draft.duration = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _QuantityCalc(index: index, draft: draft, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Champ « Médicament (DCI) » d'une ligne existante (#4989, maquette
/// design-v2 `.acp`/`.aci`) : remplace le `NubiaTextField` nu par une
/// recherche sur référentiel — le nom ne se tape plus, il se choisit. Tant
/// qu'aucun médicament n'est choisi (ni saisi via un modèle, #4986), affiche
/// la barre de recherche et ses résultats ; une fois un libellé présent,
/// affiche le nom (+ la forme galénique si connue) avec une action pour
/// changer de sélection. Même logique de recherche que
/// `_AddItemSearchField`, dupliquée ici car les deux champs ont des états
/// affichés différents (ajout d'une ligne vs. édition de la ligne
/// existante).
class _MedicationSearchField extends StatefulWidget {
  const _MedicationSearchField({
    required this.index,
    required this.draft,
    required this.onChanged,
  });

  final int index;
  final _ItemDraft draft;
  final VoidCallback onChanged;

  @override
  State<_MedicationSearchField> createState() =>
      _MedicationSearchFieldState();
}

class _MedicationSearchFieldState extends State<_MedicationSearchField> {
  final _controller = TextEditingController();
  List<MedicationReference> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty ||
        !GetIt.instance.isRegistered<SearchMedicationReferencesUseCase>()) {
      setState(() => _results = const []);
      return;
    }
    final result = await GetIt.instance<SearchMedicationReferencesUseCase>()(
      query: query,
    );
    if (!mounted) return;
    setState(() => _results = result.getOrElse(() => const []));
  }

  void _select(MedicationReference reference) {
    widget.draft.selectReference(reference);
    _controller.clear();
    setState(() => _results = const []);
    widget.onChanged();
  }

  void _clear() {
    widget.draft.clearReference();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    if (draft.label.text.trim().isNotEmpty) {
      return ListRow(
        key: Key('item_${widget.index}_label'),
        title: draft.label.text,
        subtitle: draft.reference?.galenicForm,
        showDivider: false,
        leading: const Icon(Icons.medication_outlined, size: 22),
        trailing: IconButton(
          key: Key('item_${widget.index}_label_clear'),
          tooltip: 'Changer de médicament',
          icon: const Icon(Icons.close, size: 18),
          onPressed: _clear,
        ),
      );
    }

    return Column(
      key: Key('item_${widget.index}_label'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NubiaSearchBar(
          key: Key('item_${widget.index}_label_search'),
          controller: _controller,
          hint: 'Rechercher un médicament (DCI)…',
          onChanged: _search,
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          NubiaCard(
            key: Key('item_${widget.index}_label_results'),
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final reference in _results)
                  ListRow(
                    key: Key(
                        'item_${widget.index}_label_result_${reference.id}'),
                    title: reference.dci,
                    subtitle: '${reference.galenicForm} · DCI',
                    trailing: TherapeuticClassLabel(
                      therapeuticClass: reference.therapeuticClass,
                    ),
                    onTap: () => _select(reference),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Affordance d'ajout d'une ligne médicament (#4987, maquette design-v2) :
/// remplace l'ancien bouton plein « Ajouter un médicament » par un champ de
/// recherche — choisir un résultat de l'autocomplétion est l'unique geste
/// d'ajout. Le contenu du référentiel (ticket « recherche référentiel DCI »)
/// n'est pas encore câblé dans le DI : tant que
/// [SearchMedicationReferencesUseCase] n'y est pas enregistré, le champ reste
/// un shell fonctionnel sans suggestion, prêt à s'activer sans autre
/// changement ici.
class _AddItemSearchField extends StatefulWidget {
  const _AddItemSearchField({required this.enabled, required this.onSelected});

  final bool enabled;
  final ValueChanged<MedicationReference> onSelected;

  @override
  State<_AddItemSearchField> createState() => _AddItemSearchFieldState();
}

class _AddItemSearchFieldState extends State<_AddItemSearchField> {
  final _controller = TextEditingController();
  List<MedicationReference> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty ||
        !GetIt.instance.isRegistered<SearchMedicationReferencesUseCase>()) {
      setState(() => _results = const []);
      return;
    }
    final result = await GetIt.instance<SearchMedicationReferencesUseCase>()(
      query: query,
    );
    if (!mounted) return;
    setState(() => _results = result.getOrElse(() => const []));
  }

  void _select(MedicationReference reference) {
    widget.onSelected(reference);
    _controller.clear();
    setState(() => _results = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NubiaSearchBar(
          key: const Key('add_item_button'),
          controller: _controller,
          hint: 'Rechercher un médicament (DCI)…',
          enabled: widget.enabled,
          onChanged: _search,
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 8),
          NubiaCard(
            key: const Key('add_item_results'),
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final reference in _results)
                  ListRow(
                    key: Key('add_item_result_${reference.id}'),
                    title: reference.dci,
                    subtitle: '${reference.galenicForm} · DCI',
                    trailing: Text(
                      reference.therapeuticClass,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () => _select(reference),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Encart de quantité calculée (#4992, maquette design-v2 `.calc`) : remplace
/// le champ libre « Quantité » par dose × fréquence × durée, avec une action
/// « Modifier » pour surcharger manuellement quand le calcul échoue ou ne
/// convient pas.
class _QuantityCalc extends StatelessWidget {
  const _QuantityCalc({
    required this.index,
    required this.draft,
    required this.onChanged,
  });

  final int index;
  final _ItemDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (draft.overridingQuantity) {
      return NubiaTextField(
        key: Key('item_${index}_quantity'),
        controller: draft.quantityOverride,
        label: 'Quantité',
        hint: 'ex. 1 boîte',
        onChanged: (_) => onChanged(),
      );
    }

    final calculated = draft.calculatedQuantity;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: Key('item_${index}_quantity_calc'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NubiaColors.brand50,
        border: Border.all(color: NubiaColors.brand200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined,
              size: 20, color: NubiaColors.brand700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              calculated != null
                  ? 'Quantité calculée : ${calculated.label}'
                  : 'Quantité calculée : renseignez la posologie et la '
                      'durée pour la calculer.',
              style: textTheme.bodyMedium?.copyWith(
                color: NubiaColors.brand700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          NubiaButton(
            key: Key('item_${index}_quantity_modify'),
            label: 'Modifier',
            variant: NubiaButtonVariant.tertiary,
            size: NubiaButtonSize.sm,
            onPressed: () {
              draft.quantityOverride.text = calculated?.label ?? '';
              draft.overridingQuantity = true;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Ordonnance créée (brouillon) : relecture des lignes + signature.
class _DraftReview extends StatelessWidget {
  const _DraftReview({
    required this.prescription,
    required this.signing,
    required this.applyingTemplate,
    required this.onSign,
    required this.onSignAndSendToPharmacy,
  });
  final Prescription prescription;
  final bool signing;
  final bool applyingTemplate;
  final VoidCallback onSign;
  final VoidCallback onSignAndSendToPharmacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final busy = signing || applyingTemplate;

    return Column(
      key: const Key('ordonnance_draft_review'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${prescription.items.length} médicament(s)',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: cs.onSurface),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const StatusPill(
                      label: 'Brouillon',
                      variant: StatusPillVariant.info,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                NubiaButton(
                  key: const Key('use_template_button'),
                  label: 'Utiliser un modèle',
                  variant: NubiaButtonVariant.secondary,
                  icon: Icons.description_outlined,
                  isLoading: applyingTemplate,
                  onPressed: busy
                      ? null
                      : () async {
                          final bloc = context.read<OrdonnancesBloc>();
                          final template =
                              await PrescriptionTemplatePicker.show(context,
                                  loadTemplates: bloc.loadTemplates);
                          if (template != null) {
                            bloc.add(OrdonnancesApplyTemplateRequested(
                              prescriptionId: prescription.id,
                              templateId: template.id,
                            ));
                          }
                        },
                ),
                const SizedBox(height: 8),
                NubiaButton(
                  key: const Key('sign_ordonnance_button'),
                  label: 'Signer l\'ordonnance',
                  icon: Icons.draw_outlined,
                  isLoading: signing,
                  onPressed: busy ? null : onSign,
                ),
                const SizedBox(height: 8),
                NubiaButton(
                  key: const Key('sign_and_send_to_pharmacy_button'),
                  label: 'Signer et envoyer à la pharmacie',
                  variant: NubiaButtonVariant.secondary,
                  icon: Icons.local_pharmacy,
                  isLoading: signing,
                  onPressed: busy ? null : onSignAndSendToPharmacy,
                ),
                const _EidasImmutabilityNotice(),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: prescription.items.length,
            itemBuilder: (context, i) {
              final item = prescription.items[i];
              return ListRow(
                key: Key('draft_item_$i'),
                title: item.label,
                subtitle: '${item.posology} — ${item.duration}',
                leading: const Icon(Icons.medication_outlined, size: 22),
                trailing: Text(
                  item.quantity,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Mention affichée avant le geste de signature : la signature électronique
/// eIDAS rend l'ordonnance horodatée et non modifiable (le brouillon, lui,
/// reste réversible tant qu'il n'est pas signé).
class _EidasImmutabilityNotice extends StatelessWidget {
  const _EidasImmutabilityNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              const TextSpan(
                text: 'Signature électronique ',
                children: [
                  TextSpan(
                    text: 'eIDAS',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' · l\'ordonnance devient un document horodaté '
                        'et non modifiable.',
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SignedConfirmation extends StatelessWidget {
  const _SignedConfirmation({required this.prescription});
  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return Center(
      key: const Key('ordonnance_signed_confirmation'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: tokens.successBg,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.check_rounded, size: 48, color: tokens.successFg),
            ),
            const SizedBox(height: 20),
            Text(
              'Ordonnance signée',
              style: theme.textTheme.titleLarge?.copyWith(color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '${prescription.items.length} médicament(s) prescrits',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SendToPharmacyCard(prescription: prescription),
            const SizedBox(height: 16),
            NubiaButton(
              key: const Key('back_to_ordonnances_button'),
              label: 'Retour aux ordonnances',
              variant: NubiaButtonVariant.secondary,
              onPressed: () => context
                  .go('/ordonnances?patientId=${prescription.patientId}'),
            ),
          ],
        ),
      ),
    );
  }
}
