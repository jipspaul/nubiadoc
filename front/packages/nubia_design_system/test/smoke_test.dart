import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

void main() {
  test('NubiaColors.brand700 est défini', () {
    expect(NubiaColors.brand700, const Color(0xFF047857));
  });

  test('NubiaColors.brand600 est défini', () {
    expect(NubiaColors.brand600, const Color(0xFF059669));
  });
}
