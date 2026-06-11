import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/domain/value_objects/amount_cents.dart';

void main() {
  group('AmountCents', () {
    test('accepts zero', () {
      const a = AmountCents(0);
      expect(a.value, 0);
    });

    test('accepts positive value', () {
      const a = AmountCents(125000);
      expect(a.value, 125000);
    });

    test('rejects negative value via assert', () {
      expect(() => AmountCents(-1), throwsA(isA<AssertionError>()));
    });

    test('equality is value-based', () {
      expect(const AmountCents(100), equals(const AmountCents(100)));
      expect(const AmountCents(100), isNot(equals(const AmountCents(101))));
    });

    test('toString delegates to CurrencyUtils.format', () {
      expect(const AmountCents(125000).toString(), '1\u00A0250,00\u00A0€');
    });
  });

  group('CurrencyUtils.format', () {
    test('formats zero', () {
      expect(CurrencyUtils.format(0), '0,00\u00A0€');
    });

    test('formats cents below 100 with leading zero', () {
      expect(CurrencyUtils.format(5), '0,05\u00A0€');
    });

    test('formats exact euro', () {
      expect(CurrencyUtils.format(100), '1,00\u00A0€');
    });

    test('formats thousands with narrow-no-break space', () {
      expect(CurrencyUtils.format(125000), '1\u00A0250,00\u00A0€');
    });

    test('formats large amount', () {
      expect(CurrencyUtils.format(1000000), '10\u00A0000,00\u00A0€');
    });

    test('preserves remainder < 10 with leading zero', () {
      expect(CurrencyUtils.format(101), '1,01\u00A0€');
    });
  });
}
