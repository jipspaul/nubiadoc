import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  test('inAppPackages contient les 4 apps Flutter', () {
    expect(
      NubiaObservability.inAppPackages,
      containsAll(const [
        'package:app_patient',
        'package:app_practicien',
        'package:app_secretariat',
        'package:app_pharmacie',
      ]),
    );
  });
}
