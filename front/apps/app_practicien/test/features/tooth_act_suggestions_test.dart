//! Tests : table acte → statut de dent proposé (module dentaire, lot 3).
//! Pré-remplissage de formulaire UNIQUEMENT — jamais d'écriture automatique.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/consultation_clinique/modules/dentaire/tooth_act_suggestions.dart';

void main() {
  test('actes connus → statut proposé', () {
    expect(
      suggestedToothStatusForAct(
          ccamCode: 'HBLD036', label: 'Pose d\'implant intra-osseux'),
      'implant',
    );
    expect(
      suggestedToothStatusForAct(
          ccamCode: 'HBLD634', label: 'Pose d\'une couronne céramique'),
      'couronne',
    );
    expect(
      suggestedToothStatusForAct(
          ccamCode: 'HBGD036', label: 'Avulsion d\'une dent permanente'),
      'absent',
    );
    expect(
      suggestedToothStatusForAct(
          ccamCode: 'HBMD053', label: 'Restauration par matériau composite'),
      'obture',
    );
  });

  test('couronne sur implant → implant (mot le plus spécifique en tête)', () {
    expect(
      suggestedToothStatusForAct(
          ccamCode: 'X', label: 'Pose de couronne sur implant'),
      'implant',
    );
  });

  test('acte sans correspondance → null (aucun dialogue proposé)', () {
    expect(
      suggestedToothStatusForAct(
          ccamCode: 'HBQK002', label: 'Radiographie rétro-alvéolaire'),
      isNull,
    );
    expect(
      suggestedToothStatusForAct(ccamCode: 'HBJD001', label: 'Détartrage'),
      isNull,
    );
  });
}
