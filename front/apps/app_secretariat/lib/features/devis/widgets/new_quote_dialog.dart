import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Devis à créer (#6757) : patient + lignes saisies dans [NewQuoteDialog],
/// avant `POST /v1/cabinet/quotes` (`CreateCabinetQuoteUseCase`).
class NewQuoteDraft {
  const NewQuoteDraft({required this.patientId, required this.items});

  final String patientId;
  final List<QuoteLineItem> items;
}

/// Dialogue « Nouveau devis » (#6757) — point d'entrée de création absent de
/// l'écran Devis secrétariat alors que l'API le permet déjà
/// (`POST /v1/cabinet/quotes`). Contrairement au dialogue praticien
/// (`app_practicien/.../devis/widgets/new_quote_dialog.dart`), le
/// secrétariat n'arrive pas depuis la fiche d'un patient déjà connu : il
/// doit d'abord le rechercher (même recherche serveur débouncée que
/// `agenda_page.dart`, #7350).
Future<NewQuoteDraft?> showNewQuoteDialog(BuildContext context) {
  return showDialog<NewQuoteDraft>(
    context: context,
    builder: (_) => const NewQuoteDialog(),
  );
}

class NewQuoteDialog extends StatefulWidget {
  const NewQuoteDialog({super.key});

  @override
  State<NewQuoteDialog> createState() => _NewQuoteDialogState();
}

class _NewQuoteDialogState extends State<NewQuoteDialog> {
  CabinetPatient? _selectedPatient;
  final _patientSearchCtrl = TextEditingController();
  String _patientQuery = '';
  List<CabinetPatient> _searchResults = const [];
  bool _searchingPatients = false;
  String? _patientsError;
  Timer? _patientSearchDebounce;

  final List<_LineDraft> _lines = [_LineDraft()];
  String? _error;

  @override
  void dispose() {
    _patientSearchDebounce?.cancel();
    _patientSearchCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// Recherche patient serveur débouncée (même convention que
  /// `agenda_page.dart._onPatientQueryChanged`, #7350) : la patientèle
  /// dépasse la taille d'une page, un filtrage local serait incomplet.
  void _onPatientQueryChanged(String value) {
    setState(() => _patientQuery = value);
    _patientSearchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchingPatients = false;
        _patientsError = null;
      });
      return;
    }
    _patientSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchPatients(trimmed),
    );
  }

  Future<void> _searchPatients(String query) async {
    setState(() {
      _searchingPatients = true;
      _patientsError = null;
    });
    final result = await GetIt.instance<ListCabinetPatientsUseCase>()(q: query);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _searchingPatients = false;
        _patientsError = failure.message;
      }),
      (patients) => setState(() {
        _searchingPatients = false;
        _searchResults = patients;
      }),
    );
  }

  Widget _buildPatientField() {
    final selected = _selectedPatient;
    if (selected != null) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Patient *'),
        child: Row(
          key: const Key('new_quote_patient_selected_row'),
          children: [
            Expanded(child: Text(selected.fullName)),
            IconButton(
              key: const Key('new_quote_patient_selected_clear'),
              icon: const Icon(Icons.close),
              tooltip: 'Changer de patient',
              onPressed: () => setState(() {
                _selectedPatient = null;
                _patientQuery = '';
                _patientSearchCtrl.clear();
              }),
            ),
          ],
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patient *',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        NubiaSearchBar(
          key: const Key('new_quote_patient_search_field'),
          controller: _patientSearchCtrl,
          hint: 'Rechercher un patient par nom',
          onChanged: _onPatientQueryChanged,
        ),
        if (_patientQuery.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          if (_searchingPatients)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                key: Key('new_quote_patient_search_loading'),
              ),
            )
          else if (_patientsError != null)
            Text(
              _patientsError!,
              key: const Key('new_quote_patient_search_error'),
              style: TextStyle(color: cs.error),
            )
          else if (_searchResults.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Aucun patient trouvé',
                key: Key('new_quote_patient_search_empty'),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                key: const Key('new_quote_patient_search_results'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in _searchResults)
                      ListTile(
                        key: Key('new_quote_patient_option_${p.id}'),
                        dense: true,
                        title: Text(p.fullName),
                        onTap: () => setState(() {
                          _selectedPatient = p;
                          _patientQuery = '';
                          _patientSearchCtrl.clear();
                        }),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau devis'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPatientField(),
              const SizedBox(height: 16),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LineRow(
                    index: i,
                    draft: _lines[i],
                    onRemove: _lines.length > 1
                        ? () => setState(() => _lines.removeAt(i))
                        : null,
                  ),
                ),
              TextButton.icon(
                key: const Key('new_quote_add_line'),
                onPressed: () => setState(() => _lines.add(_LineDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une ligne'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('new_quote_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          key: const Key('confirm_new_quote_button'),
          onPressed: _onConfirm,
          child: const Text('Créer'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final patient = _selectedPatient;
    if (patient == null) {
      setState(() => _error = 'Sélectionnez un patient.');
      return;
    }
    final items = <QuoteLineItem>[];
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final label = line.labelController.text.trim();
      if (label.isEmpty) continue;
      final amountCents = _parseAmountCents(line.amountController.text);
      if (amountCents == null || amountCents <= 0) {
        setState(() => _error = 'Montant invalide ligne ${i + 1}.');
        return;
      }
      items.add(QuoteLineItem(
        id: '',
        label: label,
        totalCents: amountCents,
        amoShareCents: 0,
        amcShareCents: 0,
        patientShareCents: amountCents,
      ));
    }
    if (items.isEmpty) {
      setState(() => _error =
          'Ajoutez au moins une ligne avec un libellé et un montant.');
      return;
    }
    Navigator.of(context).pop(
      NewQuoteDraft(patientId: patient.id, items: items),
    );
  }

  int? _parseAmountCents(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final euros = double.tryParse(normalized);
    if (euros == null) return null;
    return (euros * 100).round();
  }
}

class _LineDraft {
  final labelController = TextEditingController();
  final amountController = TextEditingController();

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.index,
    required this.draft,
    required this.onRemove,
  });

  final int index;
  final _LineDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: NubiaTextField(
            key: Key('new_quote_line_label_$index'),
            controller: draft.labelController,
            label: 'Libellé',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: NubiaTextField(
            key: Key('new_quote_line_amount_$index'),
            controller: draft.amountController,
            label: 'Montant (€)',
          ),
        ),
        if (onRemove != null)
          IconButton(
            key: Key('new_quote_line_remove_$index'),
            icon: const Icon(Icons.close),
            tooltip: 'Retirer cette ligne',
            onPressed: onRemove,
          ),
      ],
    );
  }
}
