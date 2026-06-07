// lib/presentation/widgets/nubia_card.dart
import 'package:flutter/material.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// États du [NubiaCard].
enum NubiaCardState {
  /// Carte statique non interactive.
  static_,

  /// Carte cliquable avec effet ripple.
  interactive,

  /// Carte mise en avant (bordure primaire, fond subtil).
  selected,
}

/// Carte Nubia : statique, interactive ou sélectionnée.
///
/// - [state] : `static_` / `interactive` / `selected`.
/// - [child] : contenu de la carte.
/// - [onTap] : callback tap (state `interactive`).
/// - [padding] : padding interne (défaut 16 px de tous les côtés).
class NubiaCard extends StatelessWidget {
  const NubiaCard({
    super.key,
    required this.child,
    this.state = NubiaCardState.static_,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final NubiaCardState state;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final Color backgroundColor = state == NubiaCardState.selected
        ? tokens.primarySubtleBg
        : cs.surface;

    final BorderSide borderSide = state == NubiaCardState.selected
        ? BorderSide(color: cs.primary, width: 1.5)
        : BorderSide(color: tokens.borderSubtle);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: borderSide,
    );

    final Widget content = Padding(padding: padding, child: child);

    if (state == NubiaCardState.interactive) {
      return Material(
        color: backgroundColor,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Material(
      color: backgroundColor,
      shape: shape,
      child: content,
    );
  }
}
