import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/src/remote/medical_record/medical_record_dto.dart';

void main() {
  group('MedicalRecordSummaryDto', () {
    test(
        'fromJson affiche les allergènes plutôt que les Map bruts (#6460)',
        () {
      final dto = MedicalRecordSummaryDto.fromJson({
        'allergies': [
          {'severity': 'high', 'substance': 'pénicilline'},
          {'source': 'questionnaire_patient', 'text': 'latex'},
          'Iode',
          {'name': 'Aspirine'},
          {'label': 'Fruits à coque'},
        ],
        'treatments': [],
      });

      expect(dto.allergies, [
        'pénicilline',
        'latex',
        'Iode',
        'Aspirine',
        'Fruits à coque',
      ]);
    });

    test('fromJson replie sur toString() pour une entrée sans clé connue',
        () {
      final dto = MedicalRecordSummaryDto.fromJson({
        'allergies': [
          {'unknown': 'value'},
        ],
        'treatments': [],
      });

      expect(dto.allergies, ['{unknown: value}']);
    });
  });
}
