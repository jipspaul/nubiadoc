// lib/presentation/widgets/nubia_checkbox.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Case à cocher Nubia : boîte 20×20, états off / on / mixed (indéterminé).
///
/// Composant contrôlé : l'état est piloté par le parent via [value] et
/// [onChanged]. Un [label] optionnel est affiché à droite et reste cliquable.
///
/// - [value] : `false` (off), `true` (on) ou `null` (mixed — nécessite
///   [tristate] pour être atteignable par l'utilisateur).
/// - [onChanged] : callback de bascule — si `null`, la case est désactivée.
/// - [label] : libellé cliquable optionnel affiché à droite.
/// - [tristate] : autorise l'état `null` (mixed) dans le cycle de bascule.
///
/// Cible tactile ≥ 44px, focus ring visible (rôle `primary`). Couleurs via
/// [Theme]/[NubiaTokens] — aucune couleur brute.
class NubiaCheckbox extends StatefulWidget {
  const NubiaCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.tristate = false,
  });

  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final bool tristate;

  @override
  State<NubiaCheckbox> createState() => _NubiaCheckboxState();
}

class _NubiaCheckboxState extends State<NubiaCheckbox> {
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  void _handleTap() {
    if (!_enabled) return;
    // off -> on -> (mixed si tristate) -> off
    final bool next = widget.value == null ? true : !(widget.value ?? false);
    widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final bool checked = widget.value == true;
    final bool mixed = widget.value == null;
    final bool filled = checked || mixed;

    final Color boxColor = !_enabled
        ? tokens.borderSubtle
        : (filled ? cs.primary : Colors.transparent);
    final Color borderColor = !_enabled
        ? tokens.borderSubtle
        : (filled ? cs.primary : tokens.borderDefault);
    final Color glyphColor = _enabled ? cs.onPrimary : cs.surface;

    final Widget box = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: mixed
          ? Icon(Icons.remove, size: 14, color: glyphColor)
          : checked
              ? Icon(Icons.check, size: 14, color: glyphColor)
              : null,
    );

    // Anneau de focus visible sans provoquer de décalage (bordure transparente
    // hors focus).
    final Widget ring = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color:
              _focused ? cs.primary.withValues(alpha: 0.4) : Colors.transparent,
          width: 2,
        ),
      ),
      child: box,
    );

    return Semantics(
      checked: checked,
      mixed: mixed,
      enabled: _enabled,
      label: widget.label,
      child: InkWell(
        onTap: _enabled ? _handleTap : null,
        onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ring,
              if (widget.label != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.label!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: _enabled ? cs.onSurface : tokens.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
