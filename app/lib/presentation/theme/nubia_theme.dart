// TODO: implement from design/03-design-system/03-flutter-theme.md (issue #434)
import 'package:flutter/material.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

class NubiaTheme {
  NubiaTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF047857)),
        extensions: const [NubiaTokens.light],
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF047857),
          brightness: Brightness.dark,
        ),
        extensions: const [NubiaTokens.dark],
      );
}
