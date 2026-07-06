import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';

import 'package:nubia_data/src/remote/account/account_api.dart';
import 'package:nubia_data/src/remote/account/account_dto.dart';
import 'package:nubia_data/src/repositories/account_repository_impl.dart';

class MockAccountApi extends Mock implements AccountApi {}

const _dto = HealthCoverageDto(
  regime: 'regime_general',
  amc: 'QA Mutuelle',
  numeroAdherent: '',
);

void main() {
  late MockAccountApi api;
  late AccountRepositoryImpl repo;

  setUp(() {
    api = MockAccountApi();
    repo = AccountRepositoryImpl(api);
  });

  group('updateCoverage — mutuelle sans numéro adhérent (#3434)', () {
    test(
        'amc renseigné + numeroAdherent null → envoie quand même la clé '
        'numero_adherent (chaîne vide) pour éviter le 422 "missing field"',
        () async {
      when(() => api.updateCoverage(any()))
          .thenAnswer((_) async => _dto);

      await repo.updateCoverage(
        regime: HealthInsuranceRegime.regimeGeneral,
        amc: 'QA Mutuelle',
      );

      final body =
          verify(() => api.updateCoverage(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['mutuelle'], {'amc': 'QA Mutuelle', 'numero_adherent': ''});
    });
  });
}
