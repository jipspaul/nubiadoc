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

  group('AccessRequest — #5259', () {
    test('AccessRequestDto.toDomain mappe état/canal/périmètre/révocation',
        () {
      final dto = AccessRequestDto.fromJson({
        'id': 'ar-1',
        'first_name': 'Jean',
        'last_name': 'Dupont',
        'relationship': 'conjoint',
        'status': 'refusee',
        'channel': 'sms',
        'scope': ['rendez_vous', 'documents'],
        'revoked_at': '2026-08-01T00:00:00.000Z',
      });

      final domain = dto.toDomain();

      expect(domain.relationship, DependentRelationship.conjoint);
      expect(domain.status, AccessRequestStatus.refusee);
      expect(domain.channel, AccessRequestChannel.sms);
      expect(
        domain.grantedScope,
        {AccessRight.rendezVous, AccessRight.documents},
      );
      expect(domain.revokedAt, DateTime.parse('2026-08-01T00:00:00.000Z'));
    });

    test('status inconnu/absent retombe sur envoyee, canal inconnu sur email',
        () {
      final dto = AccessRequestDto.fromJson({
        'id': 'ar-2',
        'first_name': 'Marie',
        'last_name': 'Martin',
        'status': 'un_statut_inconnu',
        'channel': 'un_canal_inconnu',
      });

      final domain = dto.toDomain();

      expect(domain.status, AccessRequestStatus.envoyee);
      expect(domain.channel, AccessRequestChannel.email);
      expect(domain.grantedScope, isEmpty);
    });

    test('sendAccessRequest envoie relationship/channel/scope mappés en '
        'chaînes API', () async {
      final dto = AccessRequestDto.fromJson({
        'id': 'ar-3',
        'first_name': 'Jean',
        'last_name': 'Dupont',
        'relationship': 'conjoint',
        'status': 'envoyee',
        'channel': 'email',
      });
      when(() => api.sendAccessRequest(any())).thenAnswer((_) async => dto);

      await repo.sendAccessRequest(
        firstName: 'Jean',
        lastName: 'Dupont',
        relationship: DependentRelationship.conjoint,
        channel: AccessRequestChannel.email,
        scope: const {AccessRight.rendezVous, AccessRight.dossierMedical},
        email: 'jean@example.com',
      );

      final body =
          verify(() => api.sendAccessRequest(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['relationship'], 'conjoint');
      expect(body['channel'], 'email');
      expect(
        (body['scope'] as List).toSet(),
        {'rendez_vous', 'dossier_medical'},
      );
      expect(body['email'], 'jean@example.com');
      expect(body.containsKey('phone'), isFalse);
    });

    test('revokeAccess délègue l\'id à l\'API', () async {
      when(() => api.revokeAccess('ar-1')).thenAnswer((_) async {});

      await repo.revokeAccess('ar-1');

      verify(() => api.revokeAccess('ar-1')).called(1);
    });
  });
}
