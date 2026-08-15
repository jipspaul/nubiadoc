import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

void main() {
  group('formatQuoteCents', () {
    test('formate un montant simple avec virgule décimale', () {
      expect(formatQuoteCents(2480), '24,80 €');
    });

    test('omet la partie décimale quand elle est nulle', () {
      expect(formatQuoteCents(206000), '2 060 €');
    });

    test('groupe les milliers avec une espace fine insécable', () {
      expect(formatQuoteCents(123456789), '1 234 567,89 €');
    });

    test('préfixe un montant négatif par un − typographique', () {
      expect(formatQuoteCents(-1636), '−16,36 €');
    });
  });

  group('formatQuoteCents avec alwaysShowDecimals', () {
    test('affiche les décimales même nulles pour un montant en milliers', () {
      expect(
        formatQuoteCents(146000, alwaysShowDecimals: true),
        '1 460,00 €',
      );
    });

    test('affiche « 0,00 € » pour un montant nul', () {
      expect(formatQuoteCents(0, alwaysShowDecimals: true), '0,00 €');
    });

    test('affiche les décimales existantes avec les milliers groupés', () {
      expect(
        formatQuoteCents(163592, alwaysShowDecimals: true),
        '1 635,92 €',
      );
    });
  });
}
