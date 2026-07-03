// lib/presentation/widgets/nubia_radio.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Bouton radio Nubia : cercle 20×20, sélection unique dans un groupe.
///
/// Composant contrôlé générique : le parent fournit la [value] de ce bouton et
/// la [groupValue] courante ; le bouton est sélectionné quand les deux sont
/// égales. Un [label] optionnel cliquable est affiché à droite.
///
/// - [value] : valeur représentée par ce bouton radio.
/// - [groupValue] : valeur actuellement sélectionnée dans le groupe.
/// - [onChanged] : callback appelé avec [value] au tap — `null` désactive.
/// - [label] : libellé cliquable optionnel.
///
/// Cible tactile ≥ 44px, focus ring visible. Couleurs via [Theme]/[NubiaTokens].
class NubiaRadio<T> extends StatefulWidget {
  const NubiaRadio({
    super.key,
    required this.value,
    required this.groupValue,
    this.onChanged,
    this.label,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T>? onChanged;
  final String? label;

  @override
  State<NubiaRadio<T>> createState() => _NubiaRadioState<T>();
}

class _NubiaRadioState<T> extends State<NubiaRadio<T>> {
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;
  bool get _selected => widget.value == widget.groupValue;

  void _handleTap() {
    if (!_enabled) return;
    widget.onChanged!(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final Color borderColor = !_enabled
        ? tokens.borderSubtle
        : (_selected ? cs.primary : tokens.borderDefault);

    final Widget circle = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      alignment: Alignment.center,
      child: _selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _enabled ? cs.primary : tokens.textTertiary,
              ),
            )
          : null,
    );

    final Widget ring = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color:
              _focused ? cs.primary.withValues(alpha: 0.4) : Colors.transparent,
          width: 2,
        ),
      ),
      child: circle,
    );

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: _selected,
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
