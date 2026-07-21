import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
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
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    context.read<PatientsBloc>().add(const PatientsLoadRequested());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Recherche serveur débattue (#4043) — 350 ms, même délai que les autres
  /// écrans de recherche du monorepo (referring_doctor_search_page.dart,
  /// pharmacy_search_page.dart).
  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context.read<PatientsBloc>().add(PatientsSearchChanged(value));
    });
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
      floatingActionButton: FloatingActionButton(
        key: const Key('patients_new_button'),
        tooltip: 'Nouveau patient',
        onPressed: () async {
          final created =
              await context.push<CabinetPatient>(AppRouter.patientNew);
          if (created != null && context.mounted) {
            context.read<PatientsBloc>().add(const PatientsLoadRequested());
          }
        },
        child: const Icon(Icons.person_add),
      ),
      body: BlocBuilder<PatientsBloc, PatientsState>(
        builder: (context, state) {
          if (state is PatientsLoaded) {
            if (state.patients.isEmpty && _query.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.person_outline,
                title: 'Aucun patient',
                subtitle: NubiaL10n.noPatients,
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Rechercher un patient',
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (state.patients.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'Aucun patient ne correspond à « $_query ».',
                        key: const Key('patients_search_no_results'),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: state.patients.length,
                      itemBuilder: (_, i) =>
                          _PatientRow(patient: state.patients[i]),
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
            const SizedBox(height: 16),
            PatientBalanceSection(patientId: patient.id),
            const SizedBox(height: 16),
            PatientTagsSection(patientId: patient.id),
            const SizedBox(height: 16),
            PatientDocumentsSection(patientId: patient.id),
          ],
        ),
      ),
    );
  }
}

/// Solde restant dû du patient (US-4.6.2, #4044/#4045). Fetch dédié via
/// `GetCabinetPatientUseCase` : la liste (`PatientsLoaded`, source de
/// `_PatientSheet`) n'expose pas `balanceDueCents`, seul le détail
/// (`GET /cabinet/patients/:id`) le renvoie.
class PatientBalanceSection extends StatefulWidget {
  const PatientBalanceSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientBalanceSection> createState() => _PatientBalanceSectionState();
}

class _PatientBalanceSectionState extends State<PatientBalanceSection> {
  int? _balanceCents;
  int? _noShowCount;
  List<GuardianshipLink>? _guardians;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await GetIt.instance<GetCabinetPatientUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (patient) => setState(() {
        _balanceCents = patient.balanceDueCents;
        // Même fetch que le solde (#4090/#4091) — pas d'appel réseau dédié.
        _noShowCount = patient.noShowCount;
        _guardians = patient.guardians;
        _loading = false;
      }),
    );
  }

  /// Centimes → "12,34 €" (#4045).
  String _formatBalance(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const NubiaSkeletonLoader(height: 20, borderRadius: 4);
    }
    if (_error != null) {
      // Best-effort : une fiche patient reste consultable même si le solde
      // ne charge pas (ex. hors-ligne) — pas de blocage de l'écran.
      return const SizedBox.shrink();
    }
    final cents = _balanceCents ?? 0;
    final noShowCount = _noShowCount;
    final guardians = _guardians ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Text(
              'Solde : ${_formatBalance(cents)}',
              key: const Key('patient_balance'),
              style: cents > 0
                  ? TextStyle(color: cs.error, fontWeight: FontWeight.w600)
                  : null,
            ),
          ],
        ),
        if (noShowCount != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_off_outlined,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                'Lapins : $noShowCount',
                key: const Key('patient_no_show_count'),
                style: noShowCount > 0
                    ? TextStyle(color: cs.error, fontWeight: FontWeight.w600)
                    : null,
              ),
            ],
          ),
        ],
        if (guardians.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                'Tuteur : ${guardians.map((g) => g.fullName).join(', ')}',
                key: const Key('patient_guardians'),
              ),
            ],
          ),
        ],
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Étiquettes', style: textTheme.titleSmall),
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
        if (_error != null)
          Text(_error!, style: TextStyle(color: cs.error))
        else if (tags == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: NubiaSkeletonLoader(height: 32, borderRadius: 16),
          )
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
    );
  }
}

/// Documents du dossier patient (GED, §4.4, #4042) — liste vide/remplie.
/// Upload hors scope ici : `POST .../documents` déjà exposé côté API,
/// reste à câbler dans un futur écran dédié si besoin.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await GetIt.instance<ListPatientDocumentsUseCase>()(widget.patientId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _error = failure.message),
      (documents) => setState(() {
        _documents = documents;
        _error = null;
      }),
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
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final documents = _documents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Documents', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_error != null)
          Text(_error!, style: TextStyle(color: cs.error))
        else if (documents == null)
          const NubiaSkeletonLoader(height: 48, borderRadius: 8)
        else if (documents.isEmpty)
          Text(
            'Aucun document.',
            key: const Key('patient_documents_empty'),
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
