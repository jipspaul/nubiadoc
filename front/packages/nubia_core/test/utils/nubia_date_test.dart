import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  group('NubiaDate.dayLong', () {
    test('formate une date ISO (chaîne) en jour long français', () {
      expect(NubiaDate.dayLong('2026-07-04'), '4 juillet 2026');
    });

    test('formate un DateTime en jour long français (heure locale)', () {
      expect(NubiaDate.dayLong(DateTime.utc(2026, 3, 12)), '12 mars 2026');
    });

    test('retourne une chaîne vide pour une entrée nulle', () {
      expect(NubiaDate.dayLong(null), '');
    });

    test('retourne une chaîne vide pour une entrée invalide', () {
      expect(NubiaDate.dayLong('pas-une-date'), '');
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

  group('NubiaDate.isSameDay', () {
    test('vrai pour deux DateTime du même jour calendaire', () {
      expect(
        NubiaDate.isSameDay(
          DateTime(2026, 7, 22, 8, 0),
          DateTime(2026, 7, 22, 23, 0),
        ),
        isTrue,
      );
    });

    test('faux pour deux jours différents', () {
      expect(
        NubiaDate.isSameDay(
          DateTime(2026, 7, 22),
          DateTime(2026, 7, 23),
        ),
        isFalse,
      );
    });

    test('convertit en heure locale avant de comparer (bug UTC #3856)', () {
      final utc = DateTime.utc(2026, 8, 16, 23, 30);
      final localSameDay = utc.toLocal();
      expect(NubiaDate.isSameDay(utc, localSameDay), isTrue);
    });
  });

  group('NubiaDate.daySeparatorLabel', () {
    test('jour courant → "Aujourd\'hui"', () {
      final now = DateTime(2026, 8, 17, 14, 30);
      expect(
        NubiaDate.daySeparatorLabel(DateTime(2026, 8, 17, 9, 0), now: now),
        "Aujourd'hui",
      );
    });

    test('veille → "Hier"', () {
      final now = DateTime(2026, 8, 17, 14, 30);
      expect(
        NubiaDate.daySeparatorLabel(DateTime(2026, 8, 16, 22, 0), now: now),
        'Hier',
      );
    });

    test('jour antérieur → "<jour de semaine> <jour> <mois>"', () {
      final now = DateTime(2026, 8, 17, 14, 30);
      // 2026-07-21 est un mardi.
      expect(
        NubiaDate.daySeparatorLabel(DateTime(2026, 7, 21, 9, 0), now: now),
        'Mardi 21 juillet',
      );
    });

    test('convertit en heure locale avant de comparer (bug UTC #3856)', () {
      final utc = DateTime.utc(2026, 8, 16, 23, 30);
      final localSameDay = utc.toLocal();
      final now = DateTime(
        localSameDay.year,
        localSameDay.month,
        localSameDay.day,
        23,
        59,
      );
      expect(NubiaDate.daySeparatorLabel(utc, now: now), "Aujourd'hui");
    });
  });

  group('NubiaDate.relative', () {
    test('même jour → HH:mm (heure locale, minutes sur 2 chiffres)', () {
      final now = DateTime(2026, 8, 17, 14, 30);
      expect(
        NubiaDate.relative(DateTime(2026, 8, 17, 9, 4), now: now),
        '09:04',
      );
    });

    test('jour antérieur → "<jour> <mois abrégé>"', () {
      final now = DateTime(2026, 8, 17, 14, 30);
      expect(
        NubiaDate.relative(DateTime(2026, 8, 8, 23, 0), now: now),
        '8 aoû',
      );
    });

    test('convertit en heure locale avant de comparer (bug UTC #3856)', () {
      // 23h UTC = jour suivant en UTC+2 (Europe/Paris, été) : ne doit pas
      // être confondu avec "aujourd'hui" côté serveur.
      final utc = DateTime.utc(2026, 8, 16, 23, 30);
      final localSameDay = utc.toLocal();
      final now = DateTime(
        localSameDay.year,
        localSameDay.month,
        localSameDay.day,
        23,
        59,
      );
      expect(
        NubiaDate.relative(utc, now: now),
        '${localSameDay.hour.toString().padLeft(2, '0')}:'
        '${localSameDay.minute.toString().padLeft(2, '0')}',
      );
    });
  });
}
