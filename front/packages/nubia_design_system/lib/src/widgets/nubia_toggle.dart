// lib/presentation/widgets/nubia_toggle.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Interrupteur (switch) Nubia : piste 44×24, pastille 20, états on/off.
///
/// Composant contrôlé : le parent pilote [value] et réagit via [onChanged].
/// Un [label] optionnel cliquable est affiché à droite.
///
/// - [value] : `true` (on) / `false` (off).
/// - [onChanged] : callback de bascule — `null` désactive l'interrupteur.
/// - [label] : libellé cliquable optionnel.
///
/// Piste on = rôle `primary`, off = `border/default`. Focus ring visible,
/// cible tactile ≥ 44px, transition 200 ms. Couleurs via [Theme]/[NubiaTokens].
class NubiaToggle extends StatefulWidget {
  const NubiaToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  State<NubiaToggle> createState() => _NubiaToggleState();
}

class _NubiaToggleState extends State<NubiaToggle> {
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  void _handleTap() {
    if (!_enabled) return;
    widget.onChanged!(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final Color trackColor = !_enabled
        ? tokens.borderSubtle
        : (widget.value ? cs.primary : tokens.borderDefault);

    final Widget track = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: 44,
      height: 24,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
        ),
      ),
    );

    final Widget ring = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              _focused ? cs.primary.withValues(alpha: 0.4) : Colors.transparent,
          width: 2,
        ),
      ),
      child: track,
    );

    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      label: widget.label,
      child: InkWell(
        onTap: _enabled ? _handleTap : null,
        onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: BorderRadius.circular(999),
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
