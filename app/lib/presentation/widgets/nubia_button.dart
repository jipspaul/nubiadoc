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
  });

  final String label;
  final VoidCallback? onPressed;
  final NubiaButtonVariant variant;
  final NubiaButtonSize size;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;
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
        return const _SizeTokens(height: 32, fontSize: 12, horizontalPadding: 12);
      case NubiaButtonSize.md:
        return const _SizeTokens(height: 44, fontSize: 14, horizontalPadding: 16);
      case NubiaButtonSize.lg:
        return const _SizeTokens(height: 52, fontSize: 16, horizontalPadding: 20);
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
          Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500)),
        ],
      );
    }
    return Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500));
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
