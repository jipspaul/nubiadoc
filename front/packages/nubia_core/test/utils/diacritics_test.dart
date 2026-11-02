import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  group('removeDiacritics', () {
    test('déplie les voyelles et consonnes accentuées courantes', () {
      expect(removeDiacritics('Congés'), 'Conges');
      expect(removeDiacritics('Équipe'), 'Equipe');
      expect(removeDiacritics('Créneaux'), 'Creneaux');
    });

    test('est un no-op sur une chaîne déjà sans diacritique', () {
      expect(removeDiacritics('Encaissements'), 'Encaissements');
    });

    test('préserve la casse de chaque caractère', () {
      expect(removeDiacritics('ÉQUIPE'), 'EQUIPE');
      expect(removeDiacritics('équipe'), 'equipe');
    });

    test('combinée à toLowerCase, rend la recherche insensible aux accents', () {
      final label = 'Congés'.toLowerCase();
      final query = 'conges';
      expect(removeDiacritics(label).contains(removeDiacritics(query)), isTrue);
    });
  });
}
