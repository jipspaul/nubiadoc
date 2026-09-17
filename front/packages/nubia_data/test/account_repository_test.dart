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

const _accountDto = AccountDto(
  id: 'acc-1',
  firstName: 'Zoe',
  lastName: 'Testeur',
  email: 'zoe@nubia.test',
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

  group('updateAccount — birth_date (#7036)', () {
    test(
        'dateOfBirth fourni → envoyé dans le corps PATCH au format ISO '
        'AAAA-MM-JJ, pas silencieusement jeté', () async {
      when(() => api.updateAccount(any())).thenAnswer((_) async => _accountDto);

      await repo.updateAccount(
        firstName: 'Zoe',
        lastName: 'Testeur',
        phone: '0612345678',
        dateOfBirth: DateTime(2006, 1, 15),
      );

      final body =
          verify(() => api.updateAccount(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['birth_date'], '2006-01-15');
    });

    test('dateOfBirth absent → aucune clé birth_date dans le corps PATCH',
        () async {
      when(() => api.updateAccount(any())).thenAnswer((_) async => _accountDto);

      await repo.updateAccount(phone: '0612345678');

      final body =
          verify(() => api.updateAccount(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body.containsKey('birth_date'), isFalse);
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

  group('setReferringDoctor — #7044', () {
    const providerDto = ReferringDoctorDto(
      providerId: '90de0000-0000-4000-8000-000000000011',
      name: 'Dr Chloé Moreau',
      specialty: 'Orthodontie',
    );
    const freeDto = ReferringDoctorDto(name: 'Dr Hors Annuaire');

    test(
        'praticien de l\'annuaire → envoie provider_id seul, sans name/'
        'specialty (que l\'API rejette par deny_unknown_fields)', () async {
      when(() => api.setReferringDoctor(any()))
          .thenAnswer((_) async => providerDto);

      await repo.setReferringDoctor(
        providerId: '90de0000-0000-4000-8000-000000000011',
        name: 'Dr Chloé Moreau',
        specialty: 'Orthodontie',
        address: '1 rue de la Paix, Lyon',
      );

      final body =
          verify(() => api.setReferringDoctor(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body, {'provider_id': '90de0000-0000-4000-8000-000000000011'});
    });

    test(
        'médecin hors annuaire → envoie free_name/free_phone/free_address, '
        'jamais name/phone/address/email', () async {
      when(() => api.setReferringDoctor(any()))
          .thenAnswer((_) async => freeDto);

      await repo.setReferringDoctor(
        name: 'Dr Hors Annuaire',
        phone: '0612345678',
        email: 'hors-annuaire@example.com',
        address: '1 rue de la Paix, Lyon',
      );

      final body =
          verify(() => api.setReferringDoctor(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body, {
        'free_name': 'Dr Hors Annuaire',
        'free_phone': '0612345678',
        'free_address': '1 rue de la Paix, Lyon',
      });
      expect(body.containsKey('email'), isFalse);
    });
  });
}
