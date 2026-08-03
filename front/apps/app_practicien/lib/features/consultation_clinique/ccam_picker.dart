import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

class CcamAct {
  final String code;
  final String label;

  /// Tarif de référence CCAM en centimes (facultatif) — sert à pré-remplir le
  /// montant dans l'éditeur d'acte (#3402).
  final int? tarifCents;

  const CcamAct({required this.code, required this.label, this.tarifCents});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CcamAct &&
          other.code == code &&
          other.label == label &&
          other.tarifCents == tarifCents;

  @override
  int get hashCode => Object.hash(code, label, tarifCents);
}

/// Brouillon d'acte saisi dans l'éditeur (#3402) : dent + montant en centimes.
class CcamActDraft {
  final String? tooth;
  final int amountCents;

  const CcamActDraft({this.tooth, required this.amountCents});
}

abstract class GetActsUseCase {
  /// [tooth] (FDI, #4118) : quand [prefix] est vide, le back classe les
  /// suggestions par usage du praticien sur des dents du même type.
  Future<List<CcamAct>> search(String prefix, {String? tooth});
}

/// Gestion des actes CCAM favoris du praticien (#4112/#4113) — épingler
/// depuis les résultats de recherche, désépingler depuis la section favoris.
abstract class FavoriteActsUseCase {
  Future<List<CcamAct>> list();
  Future<void> add(String ccamCode);
  Future<void> remove(String ccamCode);
}

class CcamPicker extends StatefulWidget {
  final GetActsUseCase useCase;

  /// `null` : pas de section favoris affichée (usages hors contexte
  /// praticien connecté — non applicable ici en pratique, mais garde le
  /// widget testable sans dépendance obligatoire, #4113).
  final FavoriteActsUseCase? favoritesUseCase;

  /// Dent pré-sélectionnée (#4048, schéma dentaire → tap sur une dent) — pré-
  /// remplit le champ dent de l'éditeur au lieu de la saisie texte libre.
  /// Reste modifiable dans l'éditeur (l'utilisateur peut corriger).
  final String? selectedTooth;

  /// Appelé une fois l'acte pleinement saisi (code + dent + montant) via
  /// l'éditeur (#3402). Le montant est en centimes ; la dent est facultative.
  final void Function({
    required String code,
    required String label,
    String? tooth,
    required int amountCents,
  }) onActSubmitted;

  const CcamPicker({
    super.key,
    required this.useCase,
    required this.onActSubmitted,
    this.selectedTooth,
    this.favoritesUseCase,
  });

  @override
  State<CcamPicker> createState() => _CcamPickerState();
}

class _CcamPickerState extends State<CcamPicker> {
  final _controller = TextEditingController();
  List<CcamAct>? _suggestions;
  List<CcamAct>? _favorites;

  /// Suggestions contextuelles à la dent sélectionnée (#4118) — affichées
  /// uniquement quand le champ de recherche est vide.
  List<CcamAct>? _toothSuggestions;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadToothSuggestions();
  }

  @override
  void didUpdateWidget(covariant CcamPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTooth != oldWidget.selectedTooth) {
      _loadToothSuggestions();
    }
  }

  Future<void> _loadToothSuggestions() async {
    final tooth = widget.selectedTooth;
    if (tooth == null || tooth.isEmpty) {
      if (_toothSuggestions != null) setState(() => _toothSuggestions = null);
      return;
    }
    final results = await widget.useCase.search('', tooth: tooth);
    if (!mounted || widget.selectedTooth != tooth) return;
    setState(() => _toothSuggestions = results.take(5).toList());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final useCase = widget.favoritesUseCase;
    if (useCase == null) return;
    final favorites = await useCase.list();
    if (!mounted) return;
    setState(() => _favorites = favorites);
  }

  bool _isFavorite(String code) =>
      _favorites?.any((f) => f.code == code) ?? false;

  Future<void> _toggleFavorite(CcamAct act) async {
    final useCase = widget.favoritesUseCase;
    if (useCase == null) return;
    if (_isFavorite(act.code)) {
      await useCase.remove(act.code);
    } else {
      await useCase.add(act.code);
    }
    await _loadFavorites();
  }

  Future<void> _onChanged(String value) async {
    if (value.length <= 3) {
      if (_suggestions != null) setState(() => _suggestions = null);
      return;
    }
    final results = await widget.useCase.search(value);
    if (!mounted) return;
    setState(() => _suggestions = results.take(8).toList());
  }

  /// Ouvre l'éditeur d'acte (dent + montant) au choix d'un code CCAM (#3402).
  /// Sans saisie, aucun acte n'est envoyé (annulation).
  Future<void> _select(CcamAct act) async {
    final draft = await showDialog<CcamActDraft>(
      context: context,
      builder: (_) => CcamActEditorDialog(
        act: act,
        initialTooth: widget.selectedTooth,
      ),
    );
    if (!mounted || draft == null) return;
    _controller.clear();
    setState(() => _suggestions = null);
    widget.onActSubmitted(
      code: act.code,
      label: act.label,
      tooth: draft.tooth,
      amountCents: draft.amountCents,
    );
  }

  Widget _favoriteToggleButton(CcamAct act) {
    final isFavorite = _isFavorite(act.code);
    return IconButton(
      key: Key('ccam_favorite_toggle_${act.code}'),
      icon: Icon(isFavorite ? Icons.push_pin : Icons.push_pin_outlined),
      tooltip: isFavorite ? 'Désépingler' : 'Épingler en favori',
      onPressed: () => _toggleFavorite(act),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final favorites = _favorites;
    final toothSuggestions = _toothSuggestions;
    // Les suggestions par dent ne s'affichent que sans recherche en cours.
    final showToothSuggestions = toothSuggestions != null &&
        toothSuggestions.isNotEmpty &&
        suggestions == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (favorites != null && favorites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Favoris',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          ListView.builder(
            key: const Key('ccam_favorites'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: favorites.length,
            itemBuilder: (context, i) => ListRow(
              key: Key('ccam_favorite_${favorites[i].code}'),
              leading: const Icon(Icons.star, size: 22),
              title: favorites[i].label,
              subtitle: favorites[i].code,
              trailing: _favoriteToggleButton(favorites[i]),
              onTap: () => _select(favorites[i]),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: NubiaTextField(
            key: const Key('ccam_search_field'),
            variant: NubiaTextFieldVariant.search,
            controller: _controller,
            onChanged: _onChanged,
            hint: 'Rechercher un acte CCAM',
          ),
        ),
        // SOUS le champ (et non au-dessus) : une section qui apparaît en
        // asynchrone au-dessus du champ décalerait son Element dans la
        // Column et casserait la connexion IME en cours de frappe.
        if (showToothSuggestions) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Suggestions pour la dent ${widget.selectedTooth}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          ListView.builder(
            key: const Key('ccam_tooth_suggestions'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: toothSuggestions.length,
            itemBuilder: (context, i) => ListRow(
              key: Key('ccam_tooth_suggestion_${toothSuggestions[i].code}'),
              leading: const Icon(Icons.auto_awesome_outlined, size: 22),
              title: toothSuggestions[i].label,
              subtitle: toothSuggestions[i].code,
              onTap: () => _select(toothSuggestions[i]),
            ),
          ),
        ],
        if (suggestions != null)
          suggestions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucun acte trouvé',
                    key: const Key('ccam_no_results'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : ListView.builder(
                  key: const Key('ccam_suggestions'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length,
                  itemBuilder: (context, i) => ListRow(
                    key: Key('ccam_act_${suggestions[i].code}'),
                    leading: const Icon(Icons.add_circle_outline, size: 22),
                    title: suggestions[i].label,
                    subtitle: suggestions[i].code,
                    trailing: widget.favoritesUseCase == null
                        ? null
                        : _favoriteToggleButton(suggestions[i]),
                    onTap: () => _select(suggestions[i]),
                  ),
                ),
      ],
    );
  }
}

/// Éditeur d'acte CCAM (#3402) : permet de saisir le **numéro de dent** et le
/// **montant** avant l'ajout. Le montant est pré-rempli avec le tarif CCAM de
/// référence si disponible. Retourne un [CcamActDraft] (ou `null` si annulé).
class CcamActEditorDialog extends StatefulWidget {
  final CcamAct act;

  /// Pré-remplissage du champ dent (#4048) — voir `CcamPicker.selectedTooth`.
  final String? initialTooth;

  const CcamActEditorDialog({super.key, required this.act, this.initialTooth});

  @override
  State<CcamActEditorDialog> createState() => _CcamActEditorDialogState();
}

class _CcamActEditorDialogState extends State<CcamActEditorDialog> {
  late final TextEditingController _toothController;
  late final TextEditingController _amountController;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    // Pré-remplissage de la dent (#4048) — reste modifiable par l'utilisateur.
    _toothController = TextEditingController(text: widget.initialTooth ?? '');
    // Pré-remplissage du montant avec le tarif de référence (#3402).
    final tarif = widget.act.tarifCents;
    _amountController = TextEditingController(
      text: tarif != null ? _centsToEuros(tarif) : '',
    );
  }

  @override
  void dispose() {
    _toothController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  static String _centsToEuros(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

  /// Parse un montant en euros saisi (« 28,64 » ou « 28.64 ») vers des centimes.
  /// Retourne `null` si la saisie est invalide.
  static int? _eurosToCents(String raw) {
    final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final euros = double.tryParse(normalized);
    if (euros == null || euros < 0) return null;
    return (euros * 100).round();
  }

  void _submit() {
    final cents = _eurosToCents(_amountController.text);
    if (cents == null) {
      setState(() => _amountError = 'Montant invalide');
      return;
    }
    final tooth = _toothController.text.trim();
    Navigator.of(context).pop(
      CcamActDraft(
        tooth: tooth.isEmpty ? null : tooth,
        amountCents: cents,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('act_editor'),
      title: Text(widget.act.label, style: textTheme.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.act.code, style: textTheme.bodySmall),
          const SizedBox(height: 16),
          NubiaTextField(
            key: const Key('act_editor_tooth_field'),
            variant: NubiaTextFieldVariant.outlined,
            controller: _toothController,
            label: 'Numéro de dent',
            hint: 'ex. 26',
          ),
          const SizedBox(height: 12),
          NubiaTextField(
            key: const Key('act_editor_amount_field'),
            variant: NubiaTextFieldVariant.amount,
            controller: _amountController,
            label: 'Montant',
            errorText: _amountError,
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('act_editor_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        NubiaButton(
          key: const Key('act_editor_submit'),
          size: NubiaButtonSize.sm,
          icon: Icons.check,
          label: 'Ajouter',
          onPressed: _submit,
        ),
      ],
    );
  }
}
