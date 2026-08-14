// lib/presentation/widgets/nubia_search_bar.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Barre de recherche Nubia : loupe leading + champ + chip lieu (option).
///
/// Hauteur 48, rayon 8 (input), bouton clear qui apparaît dès que le champ
/// est non vide. Un [locationChip] optionnel (ex. [NubiaChip]) est affiché en
/// trailing avant le bouton clear.
///
/// - [controller] : contrôleur externe optionnel ; sinon un interne est créé.
/// - [hint] : placeholder (défaut « Rechercher »).
/// - [onChanged] / [onSubmitted] : callbacks du champ.
/// - [onClear] : appelé après vidage via le bouton clear.
/// - [locationChip] : widget trailing optionnel (chip lieu).
/// - [enabled] : désactive le champ.
///
/// Couleurs via [Theme]/[NubiaTokens] — aucune couleur brute. Focus ring via la
/// bordure primaire au focus.
class NubiaSearchBar extends StatefulWidget {
  const NubiaSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Rechercher',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.locationChip,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final Widget? locationChip;
  final bool enabled;

  @override
  State<NubiaSearchBar> createState() => _NubiaSearchBarState();
}

class _NubiaSearchBarState extends State<NubiaSearchBar> {
  late final TextEditingController _controller;
  bool _ownsController = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final Color borderColor = _focused ? cs.primary : tokens.borderDefault;
    final bool hasText = _controller.text.isNotEmpty;

    return Semantics(
      textField: true,
      label: widget.hint,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: widget.enabled ? cs.surface : tokens.borderSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: _focused ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: tokens.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                textInputAction: TextInputAction.search,
                style: textTheme.bodyMedium,
                onTap: () => setState(() => _focused = true),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hint,
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: tokens.textTertiary,
                  ),
                ),
                onEditingComplete: () => setState(() => _focused = false),
              ),
            ),
            if (hasText) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: widget.enabled ? _clear : null,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: tokens.textTertiary,
                  ),
                ),
              ),
            ],
            if (widget.locationChip != null) ...[
              const SizedBox(width: 8),
              widget.locationChip!,
            ],
          ],
        ),
      ),
    );
  }
}
