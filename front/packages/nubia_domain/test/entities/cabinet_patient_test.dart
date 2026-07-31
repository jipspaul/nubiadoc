// Régression #4542 — patients avec firstName/lastName vides (import legacy)
// s'affichaient en ligne blanche dans les listes praticien/secrétariat
// ('$firstName $lastName' avec les deux vides == un simple espace).
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

CabinetPatient _patient({String firstName = '', String lastName = ''}) =>
    CabinetPatient(
      id: 'pat-1',
      cabinetId: 'cab-1',
      firstName: firstName,
      lastName: lastName,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('CabinetPatient.fullName', () {
    test('prénom et nom présents -> concaténation normale', () {
      expect(_patient(firstName: 'Marc', lastName: 'Dubois').fullName,
          'Marc Dubois');
    });

    test('prénom et nom vides (#4542) -> repli explicite', () {
      expect(_patient(firstName: '', lastName: '').fullName,
          'Patient sans nom');
    });

    test('prénom et nom composés uniquement d\'espaces (#4542) -> repli', () {
      expect(_patient(firstName: '   ', lastName: '  ').fullName,
          'Patient sans nom');
    });

    test('nom manquant -> seul le prénom est affiché (pas d\'espace final)',
        () {
      expect(_patient(firstName: 'Marc', lastName: '').fullName, 'Marc');
    });

    test('prénom manquant -> seul le nom est affiché (pas d\'espace initial)',
        () {
      expect(_patient(firstName: '', lastName: 'Dubois').fullName, 'Dubois');
    });
  });
}
