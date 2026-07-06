import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_data/nubia_data.dart';

import 'package:app_practicien/features/consultation_clinique/api_get_acts_use_case.dart';

class _MockClinicalSessionApi extends Mock implements ClinicalSessionApi {}

void main() {
  test('ApiGetActsUseCase mappe la réponse /ccam/acts en CcamAct', () async {
    final api = _MockClinicalSessionApi();
    when(() => api.searchCcamActs('detar')).thenAnswer((_) async => [
          (code: 'HBGD036', label: 'Détartrage deux arcades', tarifCents: 2864),
          (
            code: 'HBGD017',
            label: 'Détartrage complémentaire',
            tarifCents: null
          ),
        ]);

    final acts = await ApiGetActsUseCase(api).search('detar');

    expect(acts, hasLength(2));
    expect(acts.first.code, 'HBGD036');
    expect(acts.first.label, 'Détartrage deux arcades');
    // Le tarif de référence est propagé pour pré-remplir l'éditeur (#3402).
    expect(acts.first.tarifCents, 2864);
    expect(acts.last.tarifCents, isNull);
  });
}
