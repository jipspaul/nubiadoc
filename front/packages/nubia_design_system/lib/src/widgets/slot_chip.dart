// lib/presentation/widgets/slot_chip.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// États d'un [SlotChip].
enum SlotChipState {
  /// Créneau proposé, sélectionnable.
  available,

  /// Créneau retenu (fond `brand/50`, texte `brand`).
  selected,

  /// Créneau indisponible (désactivé, barré).
  unavailable,

  /// Créneau en cours de chargement (spinner).
  loading,
}

/// Puce créneau (~36 px) pour la réservation.
///
/// Quatre états : `available` / `selected` / `unavailable` / `loading`.
/// Accessible au clavier ([InkWell] focalisable + [Semantics]). Tokens
/// uniquement — rayon `sm` (8), texte `label`/600.
///
/// - [label] : libellé du créneau (ex. « 14:30 »).
/// - [state] : état visuel (défaut [SlotChipState.available]).
/// - [onTap] : callback — ignoré si `unavailable` ou `loading`.
class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.label,
    this.state = SlotChipState.available,
    this.onTap,
  });

  final String label;
  final SlotChipState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final bool selected = state == SlotChipState.selected;
    final bool enabled =
        (state == SlotChipState.available || selected) && onTap != null;

    Color background;
    Color foreground;
    Color borderColor;

    switch (state) {
      case SlotChipState.selected:
        background = tokens.primarySubtleBg;
        foreground = tokens.primarySubtleFg;
        borderColor = Colors.transparent;
      case SlotChipState.unavailable:
        background = cs.surface;
        foreground = tokens.textTertiary;
        borderColor = tokens.borderSubtle;
      case SlotChipState.loading:
      case SlotChipState.available:
        background = cs.surface;
        foreground = cs.onSurfaceVariant;
        borderColor = tokens.borderSubtle;
    }

    final Widget label0 = Text(
      label,
      style: textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: foreground,
        decoration: state == SlotChipState.unavailable
            ? TextDecoration.lineThrough
            : TextDecoration.none,
      ),
    );

    final Widget child = state == SlotChipState.loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          )
        : label0;

    final Widget chip = Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: chip,
    );
  }
}
