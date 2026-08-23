import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/consents/consents_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListConsentsUseCase extends Mock implements ListConsentsUseCase {}

class MockSetConsentUseCase extends Mock implements SetConsentUseCase {}

class MockListPatientPharmacyOrdersUseCase extends Mock
    implements ListPatientPharmacyOrdersUseCase {}

class MockGetMyPharmacyUseCase extends Mock implements GetMyPharmacyUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _consents = [
  Consent(purpose: 'marketing', granted: false),
  Consent(purpose: 'soins', granted: true),
];

PharmacyOrder _order({
  required String id,
  required PharmacyOrderStatus status,
  String? orderRef,
  DateTime? createdAt,
}) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'pharma-1',
      orderRef: orderRef,
      prescriptionId: 'presc-$id',
      status: status,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      updatedAt: createdAt ?? DateTime(2026, 1, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockListConsentsUseCase mockList;
  late MockSetConsentUseCase mockSet;
  late MockListPatientPharmacyOrdersUseCase mockListOrders;
  late MockGetMyPharmacyUseCase mockGetMyPharmacy;

  setUp(() {
    mockList = MockListConsentsUseCase();
    mockSet = MockSetConsentUseCase();
    mockListOrders = MockListPatientPharmacyOrdersUseCase();
    mockGetMyPharmacy = MockGetMyPharmacyUseCase();
    when(() => mockGetMyPharmacy()).thenAnswer((_) async => const Right(null));
  });

  ConsentsCubit makeCubit() => ConsentsCubit(
        list: mockList,
        set: mockSet,
        listPharmacyOrders: mockListOrders,
        getMyPharmacy: mockGetMyPharmacy,
      );

  group('ConsentsCubit', () {
    blocTest<ConsentsCubit, ConsentsState>(
      'load() émet ConsentsError (plein écran) sur échec de chargement',
      build: () {
        when(() => mockList())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [
        isA<ConsentsLoading>(),
        isA<ConsentsError>(),
      ],
    );

    blocTest<ConsentsCubit, ConsentsState>(
      // #5215 — un échec de toggle() ne doit jamais émettre ConsentsError
      // (plein écran) : la liste reste affichée, la bascule revient à son
      // état serveur, l'erreur est portée par ConsentsLoaded.toggleError.
      'toggle() en échec reste sur ConsentsLoaded avec toggleError, sans ConsentsError',
      seed: () => const ConsentsLoaded(_consents),
      build: () {
        when(() => mockSet(purpose: 'marketing', granted: true)).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Échec de la mise à jour.'),
          ),
        );
        return makeCubit();
      },
      act: (c) => c.toggle('marketing', true),
      expect: () => [
        isA<ConsentsLoaded>()
            .having((s) => s.consents, 'consents', _consents)
            .having((s) => s.pending, 'pending', 'marketing'),
        isA<ConsentsLoaded>()
            .having((s) => s.consents, 'consents', _consents)
            .having((s) => s.pending, 'pending', isNull)
            .having(
              (s) => s.toggleError,
              'toggleError',
              'Échec de la mise à jour.',
            ),
      ],
    );

    blocTest<ConsentsCubit, ConsentsState>(
      'toggle() en succès recharge la liste depuis le serveur',
      seed: () => const ConsentsLoaded(_consents),
      build: () {
        when(() => mockSet(purpose: 'marketing', granted: true))
            .thenAnswer((_) async => const Right(null));
        when(() => mockList()).thenAnswer(
          (_) async => const Right([
            Consent(purpose: 'marketing', granted: true),
            Consent(purpose: 'soins', granted: true),
          ]),
        );
        return makeCubit();
      },
      act: (c) => c.toggle('marketing', true),
      expect: () => [
        isA<ConsentsLoaded>().having((s) => s.pending, 'pending', 'marketing'),
        isA<ConsentsLoading>(),
        isA<ConsentsLoaded>().having(
          (s) => s.consents.firstWhere((c) => c.purpose == 'marketing').granted,
          'marketing granted',
          true,
        ),
      ],
    );
  });

  group('load() pharmacyName (#5209)', () {
    blocTest<ConsentsCubit, ConsentsState>(
      'renseigne pharmacyName depuis la pharmacie déclarée',
      build: () {
        when(() => mockList()).thenAnswer((_) async => const Right(_consents));
        when(() => mockGetMyPharmacy()).thenAnswer(
          (_) async => const Right(Pharmacy(id: 'ph1', name: 'Pharmacie du Théâtre')),
        );
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [
        isA<ConsentsLoading>(),
        isA<ConsentsLoaded>().having(
          (s) => s.pharmacyName,
          'pharmacyName',
          'Pharmacie du Théâtre',
        ),
      ],
    );

    blocTest<ConsentsCubit, ConsentsState>(
      'pharmacyName reste null sans pharmacie déclarée',
      build: () {
        when(() => mockList()).thenAnswer((_) async => const Right(_consents));
        when(() => mockGetMyPharmacy())
            .thenAnswer((_) async => const Right(null));
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [
        isA<ConsentsLoading>(),
        isA<ConsentsLoaded>().having(
          (s) => s.pharmacyName,
          'pharmacyName',
          isNull,
        ),
      ],
    );

    blocTest<ConsentsCubit, ConsentsState>(
      'pharmacyName reste null si la requête pharmacie échoue',
      build: () {
        when(() => mockList()).thenAnswer((_) async => const Right(_consents));
        when(() => mockGetMyPharmacy())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return makeCubit();
      },
      act: (c) => c.load(),
      expect: () => [
        isA<ConsentsLoading>(),
        isA<ConsentsLoaded>().having(
          (s) => s.pharmacyName,
          'pharmacyName',
          isNull,
        ),
      ],
    );
  });

  group('pendingPharmacyOrderRef (#5212)', () {
    test('renvoie la référence de la commande non terminale la plus récente',
        () async {
      when(() => mockListOrders()).thenAnswer(
        (_) async => Right([
          _order(
            id: '1',
            status: PharmacyOrderStatus.pickedUp,
            orderRef: 'CMD-OLD',
            createdAt: DateTime(2026, 1, 1),
          ),
          _order(
            id: '2',
            status: PharmacyOrderStatus.preparing,
            orderRef: 'CMD-4821',
            createdAt: DateTime(2026, 2, 1),
          ),
        ]),
      );
      final ref = await makeCubit().pendingPharmacyOrderRef();
      expect(ref, 'CMD-4821');
    });

    test('renvoie null sans commande en cours', () async {
      when(() => mockListOrders()).thenAnswer(
        (_) async => Right([
          _order(id: '1', status: PharmacyOrderStatus.pickedUp),
          _order(id: '2', status: PharmacyOrderStatus.cancelled),
        ]),
      );
      final ref = await makeCubit().pendingPharmacyOrderRef();
      expect(ref, isNull);
    });

    test('renvoie null si la commande en cours n\'a pas de référence', () async {
      when(() => mockListOrders()).thenAnswer(
        (_) async => Right([
          _order(id: '1', status: PharmacyOrderStatus.received, orderRef: null),
        ]),
      );
      final ref = await makeCubit().pendingPharmacyOrderRef();
      expect(ref, isNull);
    });

    test('renvoie null sur échec de la requête', () async {
      when(() => mockListOrders())
          .thenAnswer((_) async => const Left(NetworkFailure()));
      final ref = await makeCubit().pendingPharmacyOrderRef();
      expect(ref, isNull);
    });
  });
}
