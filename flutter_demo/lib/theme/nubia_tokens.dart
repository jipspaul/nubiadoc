// lib/theme/nubia_tokens.dart
import 'package:flutter/material.dart';

import 'nubia_colors.dart';

/// Rôles sémantiques Nubia exposés à l'UI via une [ThemeExtension].
///
/// Couche au-dessus de la palette brute ([NubiaColors]) : les widgets lisent
/// ces rôles (texte tertiaire, bordures, états succès/warning/danger/info,
/// primary-subtle, accent sable) plutôt que les couleurs brutes, via
/// `Theme.of(context).extension<NubiaTokens>()`.
///
/// Valeurs exactes : `design/03-design-system/01-tokens.md` §1.4 et §1.5.
@immutable
class NubiaTokens extends ThemeExtension<NubiaTokens> {
  final Color textTertiary;
  final Color borderSubtle;
  final Color borderDefault;
  final Color primarySubtleBg;
  final Color primarySubtleFg;
  final Color successFg;
  final Color successBg;
  final Color warningFg;
  final Color warningBg;
  final Color dangerFg;
  final Color dangerBg;
  final Color infoFg;
  final Color infoBg;
  final Color accent; // sable

  const NubiaTokens({
    required this.textTertiary,
    required this.borderSubtle,
    required this.borderDefault,
    required this.primarySubtleBg,
    required this.primarySubtleFg,
    required this.successFg,
    required this.successBg,
    required this.warningFg,
    required this.warningBg,
    required this.dangerFg,
    required this.dangerBg,
    required this.infoFg,
    required this.infoBg,
    required this.accent,
  });

  /// Rôles sémantiques en thème clair (`01-tokens.md` §1.5 colonne « Clair »).
  static const NubiaTokens light = NubiaTokens(
    textTertiary: NubiaColors.n400,
    borderSubtle: NubiaColors.n200,
    borderDefault: NubiaColors.n300,
    primarySubtleBg: NubiaColors.brand50,
    primarySubtleFg: NubiaColors.brand800,
    successFg: NubiaColors.successFg,
    successBg: NubiaColors.successBg,
    warningFg: NubiaColors.warningFg,
    warningBg: NubiaColors.warningBg,
    dangerFg: NubiaColors.dangerFg,
    dangerBg: NubiaColors.dangerBg,
    infoFg: NubiaColors.infoFg,
    infoBg: NubiaColors.infoBg,
    accent: NubiaColors.sand500,
  );

  /// Rôles sémantiques en thème sombre (`01-tokens.md` §1.5 colonne « Sombre »).
  static const NubiaTokens dark = NubiaTokens(
    textTertiary: NubiaColors.n400,
    borderSubtle: NubiaColors.n700,
    borderDefault: NubiaColors.n600,
    primarySubtleBg: Color(0xFF0B3D2E),
    primarySubtleFg: NubiaColors.brand200,
    successFg: Color(0xFF4ADE80),
    successBg: Color(0xFF14271A),
    warningFg: Color(0xFFFBBF24),
    warningBg: Color(0xFF2A1E05),
    dangerFg: Color(0xFFF87171),
    dangerBg: Color(0xFF2A1212),
    infoFg: Color(0xFF38BDF8),
    infoBg: Color(0xFF082530),
    accent: NubiaColors.sand500,
  );

  @override
  NubiaTokens copyWith({
    Color? textTertiary,
    Color? borderSubtle,
    Color? borderDefault,
    Color? primarySubtleBg,
    Color? primarySubtleFg,
    Color? successFg,
    Color? successBg,
    Color? warningFg,
    Color? warningBg,
    Color? dangerFg,
    Color? dangerBg,
    Color? infoFg,
    Color? infoBg,
    Color? accent,
  }) {
    return NubiaTokens(
      textTertiary: textTertiary ?? this.textTertiary,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      primarySubtleBg: primarySubtleBg ?? this.primarySubtleBg,
      primarySubtleFg: primarySubtleFg ?? this.primarySubtleFg,
      successFg: successFg ?? this.successFg,
      successBg: successBg ?? this.successBg,
      warningFg: warningFg ?? this.warningFg,
      warningBg: warningBg ?? this.warningBg,
      dangerFg: dangerFg ?? this.dangerFg,
      dangerBg: dangerBg ?? this.dangerBg,
      infoFg: infoFg ?? this.infoFg,
      infoBg: infoBg ?? this.infoBg,
      accent: accent ?? this.accent,
    );
  }

  @override
  NubiaTokens lerp(ThemeExtension<NubiaTokens>? other, double t) {
    if (other is! NubiaTokens) {
      return this;
    }
    return NubiaTokens(
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      primarySubtleBg: Color.lerp(primarySubtleBg, other.primarySubtleBg, t)!,
      primarySubtleFg: Color.lerp(primarySubtleFg, other.primarySubtleFg, t)!,
      successFg: Color.lerp(successFg, other.successFg, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warningFg: Color.lerp(warningFg, other.warningFg, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      dangerFg: Color.lerp(dangerFg, other.dangerFg, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      infoFg: Color.lerp(infoFg, other.infoFg, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}
