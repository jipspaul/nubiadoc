// TODO: implement from design/03-design-system/01-tokens.md §1.5 (issue #433)
import 'package:flutter/material.dart';

class NubiaTokens extends ThemeExtension<NubiaTokens> {
  const NubiaTokens();

  static const NubiaTokens light = NubiaTokens();
  static const NubiaTokens dark = NubiaTokens();

  @override
  ThemeExtension<NubiaTokens> copyWith() => const NubiaTokens();

  @override
  ThemeExtension<NubiaTokens> lerp(covariant ThemeExtension<NubiaTokens>? other, double t) => this;
}
