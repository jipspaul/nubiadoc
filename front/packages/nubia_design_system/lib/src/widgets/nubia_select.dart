// lib/presentation/widgets/nubia_select.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Élément d'un [NubiaSelect] : une [value] typée et son [label] affiché.
class NubiaSelectItem<T> {
  const NubiaSelectItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Sélecteur Nubia (dropdown) : champ valeur + chevron ouvrant une feuille.
///
/// Au tap, ouvre un bottom sheet listant les [items]. La liste devient
/// filtrable (champ de recherche) automatiquement au-delà de 8 éléments, ou si
/// [searchable] est forcé. La navigation clavier est assurée par le focus
/// traversal natif (Tab / flèches, Entrée pour valider).
///
/// États du champ fermé : par défaut / focus (bordure primaire) / désactivé.
/// Dans la feuille : l'élément sélectionné porte une coche + le rôle `primary`.
///
/// - [items] : options disponibles.
/// - [value] : valeur sélectionnée (ou `null`).
/// - [onChanged] : callback de sélection — `null` désactive le champ.
/// - [label] : libellé au-dessus du champ.
/// - [hint] : texte affiché quand aucune valeur n'est choisie.
/// - [searchable] : force (`true`) ou interdit (`false`) la recherche ; `null`
///   = automatique (recherche si plus de 8 éléments).
///
/// Rayon 8, hauteur ≥ 48. Couleurs via [Theme]/[NubiaTokens] — aucune brute.
class NubiaSelect<T> extends StatefulWidget {
  const NubiaSelect({
    super.key,
    required this.items,
    this.value,
    this.onChanged,
    this.label,
    this.hint = 'Sélectionner',
    this.searchable,
  });

  final List<NubiaSelectItem<T>> items;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String hint;
  final bool? searchable;

  @override
  State<NubiaSelect<T>> createState() => _NubiaSelectState<T>();
}

class _NubiaSelectState<T> extends State<NubiaSelect<T>> {
  bool _focused = false;
  bool _open = false;

  bool get _enabled => widget.onChanged != null && widget.items.isNotEmpty;

  NubiaSelectItem<T>? get _selectedItem {
    for (final item in widget.items) {
      if (item.value == widget.value) return item;
    }
    return null;
  }

  Future<void> _openSheet() async {
    if (!_enabled) return;
    setState(() => _open = true);
    final bool searchable = widget.searchable ?? (widget.items.length > 8);
    final T? picked = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _NubiaSelectSheet<T>(
        items: widget.items,
        selected: widget.value,
        label: widget.label,
        searchable: searchable,
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final NubiaSelectItem<T>? selected = _selectedItem;
    final bool active = _focused || _open;

    final Color borderColor = !_enabled
        ? tokens.borderSubtle
        : (active ? cs.primary : tokens.borderDefault);
    final Color valueColor = !_enabled
        ? tokens.textTertiary
        : (selected != null ? cs.onSurface : tokens.textTertiary);

    final Widget field = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _enabled ? cs.surface : tokens.borderSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: active ? 1.5 : 1),
      ),
      child: Row(
        children: [
          if (selected?.icon != null) ...[
            Icon(selected!.icon, size: 20, color: valueColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              selected?.label ?? widget.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(color: valueColor),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 20,
            color: tokens.textTertiary,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: textTheme.labelLarge?.copyWith(
              color: _enabled ? cs.onSurface : tokens.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(
          button: true,
          enabled: _enabled,
          label: widget.label,
          value: selected?.label ?? widget.hint,
          child: InkWell(
            onTap: _enabled ? _openSheet : null,
            onFocusChange: (v) => setState(() => _focused = v),
            borderRadius: BorderRadius.circular(8),
            child: field,
          ),
        ),
      ],
    );
  }
}

/// Contenu du bottom sheet du [NubiaSelect] : recherche optionnelle + liste.
class _NubiaSelectSheet<T> extends StatefulWidget {
  const _NubiaSelectSheet({
    required this.items,
    required this.selected,
    required this.searchable,
    this.label,
  });

  final List<NubiaSelectItem<T>> items;
  final T? selected;
  final bool searchable;
  final String? label;

  @override
  State<_NubiaSelectSheet<T>> createState() => _NubiaSelectSheetState<T>();
}

class _NubiaSelectSheetState<T> extends State<_NubiaSelectSheet<T>> {
  late final TextEditingController _search;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<NubiaSelectItem<T>> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items
        .where((i) => i.label.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    final items = _filtered;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.label != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(widget.label!, style: textTheme.titleLarge),
              ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: tokens.textTertiary,
                    ),
                    hintText: 'Rechercher',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Aucun résultat',
                        style: textTheme.bodyMedium?.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final bool isSelected = item.value == widget.selected;
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(item.value),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            color: isSelected
                                ? tokens.primarySubtleBg
                                : Colors.transparent,
                            child: Row(
                              children: [
                                if (item.icon != null) ...[
                                  Icon(
                                    item.icon,
                                    size: 20,
                                    color: isSelected
                                        ? cs.primary
                                        : tokens.textTertiary,
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: isSelected
                                          ? cs.primary
                                          : cs.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check,
                                    size: 20,
                                    color: cs.primary,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
