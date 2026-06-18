import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

void main() {
  group('NubiaColors', () {
    test('brand700 est la couleur primaire émeraude claire', () {
      expect(NubiaColors.brand700, const Color(0xFF047857));
    });

    test('brand600 est la couleur identité émeraude', () {
      expect(NubiaColors.brand600, const Color(0xFF059669));
    });

    test('n0 est blanc pur', () {
      expect(NubiaColors.n0, const Color(0xFFFFFFFF));
    });

    test('n900 est le noir le plus profond de la palette', () {
      expect(NubiaColors.n900, const Color(0xFF1C1917));
    });
  });
}
