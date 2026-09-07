// lib/presentation/widgets/nubia_button.dart
import 'package:flutter/material.dart';

/// Variantes visuelles du [NubiaButton].
enum NubiaButtonVariant {
  /// Fond plein — action principale.
  primary,

  /// Fond subtil / outline — action secondaire.
  secondary,

  /// Texte seul — action tertiaire.
  tertiary,

  /// Fond danger — action destructrice (suppression, annulation critique).
  destructive,
}

/// Tailles du [NubiaButton].
enum NubiaButtonSize {
  /// Petite taille : hauteur 32, label 12px.
  sm,

  /// Taille standard : hauteur 44, label 14px.
  md,

  /// Grande taille : hauteur 52, label 16px.
  lg,
}

/// Bouton Nubia : 4 variantes × 3 tailles.
///
/// - [variant] : `primary` (filled), `secondary` (outlined), `tertiary`
///   (text), `destructive` (filled rouge).
/// - [size] : `sm` / `md` / `lg`.
/// - [label] : libellé du bouton.
/// - [onPressed] : callback — si null, le bouton est désactivé.
/// - [icon] : icône leading optionnelle.
/// - [isLoading] : affiche un [CircularProgressIndicator] à la place de
///   l'icône et désactive les interactions.
class NubiaButton extends StatelessWidget {
  const NubiaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = NubiaButtonVariant.primary,
    this.size = NubiaButtonSize.md,
    this.icon,
    this.isLoading = false,
  })  : _iconOnly = false,
        _diameter = 0,
        _semanticLabel = null;

  /// Variante icône seule, circulaire (ex : envoi de message) — sans label.
  ///
  /// [diameter] : diamètre du cercle (42 par défaut).
  /// [semanticLabel] : nom accessible annoncé par les lecteurs d'écran,
  /// puisqu'une icône seule n'a aucun texte à exposer à l'arbre Semantics.
  const NubiaButton.icon({
    super.key,
    required IconData this.icon,
    this.onPressed,
    this.variant = NubiaButtonVariant.primary,
    this.isLoading = false,
    double diameter = 42,
    String? semanticLabel,
  })  : label = '',
        size = NubiaButtonSize.md,
        _iconOnly = true,
        _diameter = diameter,
        _semanticLabel = semanticLabel;

  final String label;
  final VoidCallback? onPressed;
  final NubiaButtonVariant variant;
  final NubiaButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool _iconOnly;
  final double _diameter;
  final String? _semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;

    if (_iconOnly) {
      return _IconOnlyBtn(
        icon: icon!,
        onPressed: disabled ? null : onPressed,
        variant: variant,
        isLoading: isLoading,
        diameter: _diameter,
        semanticLabel: _semanticLabel,
      );
    }

    final _SizeTokens sizeTokens = _SizeTokens.of(size);

    final Widget child = _ButtonContent(
      label: label,
      icon: icon,
      isLoading: isLoading,
      fontSize: sizeTokens.fontSize,
    );

    switch (variant) {
      case NubiaButtonVariant.primary:
        return _FilledBtn(
          onPressed: disabled ? null : onPressed,
          height: sizeTokens.height,
          horizontalPadding: sizeTokens.horizontalPadding,
          child: child,
        );
      case NubiaButtonVariant.secondary:
        return _OutlinedBtn(
          onPressed: disabled ? null : onPressed,
          height: sizeTokens.height,
          horizontalPadding: sizeTokens.horizontalPadding,
          child: child,
        );
      case NubiaButtonVariant.tertiary:
        return _TextBtn(
          onPressed: disabled ? null : onPressed,
          height: sizeTokens.height,
          horizontalPadding: sizeTokens.horizontalPadding,
          child: child,
        );
      case NubiaButtonVariant.destructive:
        return _DestructiveBtn(
          onPressed: disabled ? null : onPressed,
          height: sizeTokens.height,
          horizontalPadding: sizeTokens.horizontalPadding,
          child: child,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Size tokens
// ---------------------------------------------------------------------------

class _SizeTokens {
  const _SizeTokens({
    required this.height,
    required this.fontSize,
    required this.horizontalPadding,
  });

  final double height;
  final double fontSize;
  final double horizontalPadding;

  static _SizeTokens of(NubiaButtonSize size) {
    switch (size) {
      case NubiaButtonSize.sm:
        return const _SizeTokens(
            height: 32, fontSize: 12, horizontalPadding: 12);
      case NubiaButtonSize.md:
        return const _SizeTokens(
            height: 44, fontSize: 14, horizontalPadding: 16);
      case NubiaButtonSize.lg:
        return const _SizeTokens(
            height: 52, fontSize: 16, horizontalPadding: 20);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared content widget
// ---------------------------------------------------------------------------

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.fontSize,
    this.icon,
    this.isLoading = false,
  });

  final String label;
  final double fontSize;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: fontSize + 4,
        height: fontSize + 4,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: IconTheme.of(context).color,
        ),
      );
    }
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 2),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
    }
    return Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
    );
  }
}

// ---------------------------------------------------------------------------
// Variant wrappers
// ---------------------------------------------------------------------------

class _FilledBtn extends StatelessWidget {
  const _FilledBtn({
    required this.onPressed,
    required this.height,
    required this.horizontalPadding,
    required this.child,
  });

  final VoidCallback? onPressed;
  final double height;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  const _OutlinedBtn({
    required this.onPressed,
    required this.height,
    required this.horizontalPadding,
    required this.child,
  });

  final VoidCallback? onPressed;
  final double height;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      ),
    );
  }
}

class _TextBtn extends StatelessWidget {
  const _TextBtn({
    required this.onPressed,
    required this.height,
    required this.horizontalPadding,
    required this.child,
  });

  final VoidCallback? onPressed;
  final double height;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      ),
    );
  }
}

class _IconOnlyBtn extends StatelessWidget {
  const _IconOnlyBtn({
    required this.icon,
    required this.onPressed,
    required this.variant,
    required this.isLoading,
    required this.diameter,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final NubiaButtonVariant variant;
  final bool isLoading;
  final double diameter;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool destructive = variant == NubiaButtonVariant.destructive;
    final Color background = destructive ? cs.error : cs.primary;
    final Color foreground = destructive ? cs.onError : cs.onPrimary;

    final Widget button = SizedBox(
      width: diameter,
      height: diameter,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: background,
          foregroundColor: foreground,
          padding: EdgeInsets.zero,
          minimumSize: Size(diameter, diameter),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: isLoading
            ? SizedBox(
                width: diameter * 0.45,
                height: diameter * 0.45,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(icon, size: diameter * 0.48),
      ),
    );

    if (semanticLabel == null) return button;
    return Tooltip(message: semanticLabel!, child: button);
  }
}

class _DestructiveBtn extends StatelessWidget {
  const _DestructiveBtn({
    required this.onPressed,
    required this.height,
    required this.horizontalPadding,
    required this.child,
  });

  final VoidCallback? onPressed;
  final double height;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          minimumSize: Size(0, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      ),
    );
  }
}
