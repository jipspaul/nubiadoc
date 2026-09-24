// Quoi : formulaire de CR opératoire par sections (chirurgie, endodontie,
// parodontologie, #7153) — navigation latérale entre sections, sauvegarde
// automatique en brouillon (débounce, même logique que la note de séance,
// #4943/#4963), aperçu du rendu et finalisation.
// Quand : ouvert depuis `ActsOfSessionCard` (bouton `cr_operatoire_button`)
// pour la séance en cours.
// Pourquoi : s'appuie sur `PUT`/`GET /v1/cabinet/consultations/:id/cr` et
// `POST .../cr/finalize` (api/src/consultation_cr.rs, #7154) — brouillon
// structuré distinct de la note libre (`SaveNoteUseCase`), figé après
// finalisation.
// Modes d'échec : chargement en échec → message d'erreur plein écran
// (rien à éditer sans état de départ fiable) ; échec d'autosave/finalisation
// → bandeau d'erreur, l'utilisateur garde la main sur le formulaire déjà
// saisi (rien n'est perdu côté UI, les contrôleurs restent inchangés).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'widgets/consultation_format_utils.dart';
import 'widgets/cr_operatoire_preview.dart';
import 'widgets/cr_section_nav.dart';

const _kAutosaveDebounce = Duration(milliseconds: 800);

class CrOperatoireFormPage extends StatefulWidget {
  const CrOperatoireFormPage({super.key, required this.consultationId});

  final String consultationId;

  @override
  State<CrOperatoireFormPage> createState() => _CrOperatoireFormPageState();
}

class _CrOperatoireFormPageState extends State<CrOperatoireFormPage> {
  final Map<String, TextEditingController> _controllers = {
    for (final def in kCrSectionDefs) def.key: TextEditingController(),
  };
  Timer? _debounce;

  bool _loading = true;
  String? _loadError;
  String? _actionError;
  bool _finalized = false;
  DateTime? _lastSavedAt;
  bool _showPreview = false;
  String _selectedKey = kCrSectionDefs.first.key;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final result = await GetIt.instance<GetConsultationCrUseCase>()(
      widget.consultationId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loading = false;
        _loadError = failure.message;
      }),
      (cr) => setState(() {
        _loading = false;
        _finalized = cr.isFinalized;
        for (final section in cr.sections) {
          _controllers[section.key]?.text = section.content;
        }
      }),
    );
  }

  List<CrSectionEntry> _currentSections() => [
        for (final def in kCrSectionDefs)
          CrSectionEntry(
            key: def.key,
            title: def.title,
            content: _controllers[def.key]!.text,
          ),
      ];

  void _onSectionChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_kAutosaveDebounce, _save);
  }

  Future<void> _save() async {
    if (_finalized) return;
    final result = await GetIt.instance<SaveConsultationCrUseCase>()(
      consultationId: widget.consultationId,
      sections: _currentSections(),
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _actionError = failure.message),
      (_) => setState(() {
        _actionError = null;
        _lastSavedAt = DateTime.now();
      }),
    );
  }

  Future<void> _finalize() async {
    _debounce?.cancel();
    await _save();
    if (!mounted || _actionError != null) return;
    final result = await GetIt.instance<FinalizeConsultationCrUseCase>()(
      widget.consultationId,
    );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() => _actionError = failure.message),
      (_) => setState(() {
        _finalized = true;
        _actionError = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CR opératoire'),
        actions: [
          IconButton(
            key: const Key('cr_operatoire_preview_button'),
            tooltip: _showPreview ? 'Revenir à l\'édition' : 'Aperçu',
            icon: Icon(
              _showPreview ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
            onPressed: () => setState(() => _showPreview = !_showPreview),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              key: const Key('cr_operatoire_finalize_button'),
              onPressed: _finalized ? null : _finalize,
              child: Text(_finalized ? 'Finalisé' : 'Finaliser'),
            ),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final loadError = _loadError;
    if (loadError != null) {
      return Center(child: Text(loadError));
    }

    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Column(
      children: [
        if (_actionError != null)
          Container(
            key: const Key('cr_operatoire_error_banner'),
            width: double.infinity,
            color: tokens.dangerBg,
            padding: const EdgeInsets.all(12),
            child:
                Text(_actionError!, style: TextStyle(color: tokens.dangerFg)),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: CrSectionNav(
                  selectedKey: _selectedKey,
                  onSelect: (key) => setState(() => _selectedKey = key),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _showPreview
                    ? CrOperatoirePreview(sections: _currentSections())
                    : _buildEditor(),
              ),
            ],
          ),
        ),
        _SaveStatusBar(lastSavedAt: _lastSavedAt, finalized: _finalized),
      ],
    );
  }

  Widget _buildEditor() {
    final def =
        kCrSectionDefs.firstWhere((def) => def.key == _selectedKey);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        key: Key('cr_section_field_${def.key}'),
        controller: _controllers[def.key],
        readOnly: _finalized,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        onChanged: _onSectionChanged,
        decoration: InputDecoration(
          hintText: '${def.title}...',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _SaveStatusBar extends StatelessWidget {
  const _SaveStatusBar({required this.lastSavedAt, required this.finalized});

  final DateTime? lastSavedAt;
  final bool finalized;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final savedAt = lastSavedAt;
    return Container(
      key: const Key('cr_operatoire_save_status'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (finalized) ...[
            Icon(Icons.lock_outline, size: 16, color: tokens.textTertiary),
            const SizedBox(width: 4),
            Text(
              'Compte rendu finalisé',
              style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
            ),
          ] else if (savedAt != null) ...[
            Icon(Icons.cloud_done, size: 16, color: tokens.successFg),
            const SizedBox(width: 4),
            Text(
              'Enregistré automatiquement à ${formatTime(savedAt)}',
              style: textTheme.bodySmall?.copyWith(color: tokens.successFg),
            ),
          ],
        ],
      ),
    );
  }
}
