import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  group('NubiaDate.dayLong', () {
    test('formate une date ISO en jour long français', () {
      expect(NubiaDate.dayLong('2026-07-04'), '4 juillet 2026');
    });
  });

  group('NubiaDate.monthsSince', () {
    test('compte les mois pleins écoulés entre deux dates', () {
      expect(
        NubiaDate.monthsSince('2026-03-12', now: DateTime(2026, 8, 17)),
        5,
      );
    });

    test("n'incrémente pas le mois avant le jour anniversaire", () {
      expect(
        NubiaDate.monthsSince('2026-03-12', now: DateTime(2026, 8, 11)),
        4,
      );
    });

    test('incrémente le mois le jour anniversaire même', () {
      expect(
        NubiaDate.monthsSince('2026-03-12', now: DateTime(2026, 8, 12)),
        5,
      );
    });

    test('retourne 0 pour une date du jour même', () {
      final today = DateTime(2026, 8, 17);
      expect(NubiaDate.monthsSince('2026-08-17', now: today), 0);
    });

    test('ne retourne jamais de valeur négative pour une date future', () {
      expect(
        NubiaDate.monthsSince('2026-08-17', now: DateTime(2026, 3, 12)),
        0,
      );
    });
  });
}
