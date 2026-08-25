import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

void main() {
  group('practitionerColor', () {
    test('même practitionerId → même couleur, à tout moment (#5168)', () {
      final first = practitionerColor('pr-rousseau');
      final second = practitionerColor('pr-rousseau');
      expect(first, second);
    });

    test('practitionerId nul ou vide → gris neutre (Non attribué)', () {
      expect(practitionerColor(null), practitionerUnassignedColor);
      expect(practitionerColor(''), practitionerUnassignedColor);
    });
  });
}
