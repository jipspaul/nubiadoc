import 'package:dartz/dartz.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

class _MockProRegisterRepository extends Mock implements ProRegisterRepository {}

const _validCabinet = ProRegisterCabinetInfo(
  raisonSociale: 'Cabinet Dr Martin',
  specialite: 'Dentiste',
);

const _validPractitioner = ProRegisterPractitionerInfo(
  firstName: 'Jean',
  lastName: 'Martin',
);

ProRegisterRequest _req({
  String email = 'dr.martin@example.com',
  String password = 'Secret42!',
  ProRegisterCabinetInfo cabinet = _validCabinet,
  ProRegisterPractitionerInfo practitioner = _validPractitioner,
}) =>
    ProRegisterRequest(
      email: email,
      password: password,
      cabinet: cabinet,
      practitioner: practitioner,
    );

void main() {
  late _MockProRegisterRepository repo;
  late ProRegisterUseCase useCase;

  setUp(() {
    repo = _MockProRegisterRepository();
    useCase = ProRegisterUseCase(repo);
  });

  group('ProRegisterUseCase — validation', () {
    test('retourne ValidationFailure si e-mail invalide', () async {
      final result = await useCase.call(_req(email: 'notanemail'));
      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('devrait retourner Left'),
      );
      verifyNever(() => repo.register(any()));
    });

    test('retourne ValidationFailure si e-mail vide', () async {
      final result = await useCase.call(_req(email: ''));
      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f, isA<ValidationFailure>()), (_) => fail(''));
      verifyNever(() => repo.register(any()));
    });

    test('retourne ValidationFailure si mot de passe trop court', () async {
      final result = await useCase.call(_req(password: 'abc1'));
      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f, isA<ValidationFailure>()), (_) => fail(''));
      verifyNever(() => repo.register(any()));
    });

    test('retourne ValidationFailure si raison_sociale vide', () async {
      final result = await useCase.call(
        _req(
          cabinet: const ProRegisterCabinetInfo(
            raisonSociale: '',
            specialite: 'Dentiste',
          ),
        ),
      );
      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f, isA<ValidationFailure>()), (_) => fail(''));
      verifyNever(() => repo.register(any()));
    });

    test('retourne ValidationFailure si spécialité vide', () async {
      final result = await useCase.call(
        _req(
          cabinet: const ProRegisterCabinetInfo(
            raisonSociale: 'Cabinet Dr Martin',
            specialite: '',
          ),
        ),
      );
      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f, isA<ValidationFailure>()), (_) => fail(''));
      verifyNever(() => repo.register(any()));
    });
  });

  group('ProRegisterUseCase — délégation', () {
    test('délègue au repository quand les champs sont valides', () async {
      const session = ProSession(
        userId: 'u-1',
        cabinetId: 'cab-1',
        providerId: 'prov-1',
      );
      when(() => repo.register(any()))
          .thenAnswer((_) async => const Right(session));

      final result = await useCase.call(_req());

      expect(result.isRight(), isTrue);
      result.fold((_) => fail(''), (s) => expect(s, session));
      verify(() => repo.register(any())).called(1);
    });

    test('propage le Failure du repository', () async {
      when(() => repo.register(any()))
          .thenAnswer((_) async => const Left(NetworkFailure()));

      final result = await useCase.call(_req());

      expect(result.isLeft(), isTrue);
      result.fold((f) => expect(f, isA<NetworkFailure>()), (_) => fail(''));
    });
  });
}
