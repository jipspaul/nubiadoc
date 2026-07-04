import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/pharmacy/my_pharmacy_cubit.dart';
import 'package:app_patient/features/pharmacy/my_pharmacy_page.dart';
import 'package:app_patient/features/pharmacy/pharmacy_search_cubit.dart';

class MockPatientPharmacyRepository extends Mock
    implements PatientPharmacyRepository {}

class MockPharmacyDirectoryRepository extends Mock
    implements PharmacyDirectoryRepository {}

class MockMyPharmacyCubit extends MockCubit<MyPharmacyState>
    implements MyPharmacyCubit {}

const pharmacy = Pharmacy(
  id: 'p1',
  name: 'Pharmacie du Port',
  address: '3 rue Haute, Paris',
  distanceM: 850,
);

void main() {
  group('MyPharmacyCubit', () {
    late MockPatientPharmacyRepository repo;

    setUp(() => repo = MockPatientPharmacyRepository());

    MyPharmacyCubit buildCubit() => MyPharmacyCubit(
          getMyPharmacy: GetMyPharmacyUseCase(repo),
          setMyPharmacy: SetMyPharmacyUseCase(repo),
        );

    blocTest<MyPharmacyCubit, MyPharmacyState>(
      'charge la pharmacie déclarée (null accepté)',
      build: () {
        when(() => repo.getMyPharmacy())
            .thenAnswer((_) async => const Right(null));
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [const MyPharmacyLoading(), const MyPharmacyLoaded(null)],
    );

    blocTest<MyPharmacyCubit, MyPharmacyState>(
      'declare appelle le repo et recharge la carte',
      build: () {
        when(() => repo.setMyPharmacy('p1'))
            .thenAnswer((_) async => const Right(pharmacy));
        return buildCubit();
      },
      act: (cubit) => cubit.declare('p1'),
      expect: () =>
          [const MyPharmacyLoading(), const MyPharmacyLoaded(pharmacy)],
      verify: (_) => verify(() => repo.setMyPharmacy('p1')).called(1),
    );

    blocTest<MyPharmacyCubit, MyPharmacyState>(
      'erreur réseau → MyPharmacyError',
      build: () {
        when(() => repo.getMyPharmacy())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return buildCubit();
      },
      act: (cubit) => cubit.load(),
      expect: () => [const MyPharmacyLoading(), isA<MyPharmacyError>()],
    );
  });

  group('PharmacySearchCubit', () {
    late MockPharmacyDirectoryRepository repo;

    setUp(() => repo = MockPharmacyDirectoryRepository());

    blocTest<PharmacySearchCubit, PharmacySearchState>(
      'recherche par nom → résultats',
      build: () {
        when(() => repo.search(query: 'port'))
            .thenAnswer((_) async => const Right([pharmacy]));
        return PharmacySearchCubit(search: SearchPharmaciesUseCase(repo));
      },
      act: (cubit) => cubit.search('port'),
      expect: () => [
        const PharmacySearchLoading(),
        const PharmacySearchResults([pharmacy]),
      ],
    );

    blocTest<PharmacySearchCubit, PharmacySearchState>(
      'requête vide → Idle sans appel',
      build: () => PharmacySearchCubit(search: SearchPharmaciesUseCase(repo)),
      act: (cubit) => cubit.search('   '),
      expect: () => [const PharmacySearchIdle()],
      verify: (_) => verifyNever(() => repo.search(
          query: any(named: 'query'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusKm: any(named: 'radiusKm'))),
    );
  });

  group('MyPharmacyBody (widget)', () {
    testWidgets('aucune pharmacie → EmptyState avec CTA de déclaration',
        (tester) async {
      final cubit = MockMyPharmacyCubit();
      when(() => cubit.state).thenReturn(const MyPharmacyLoaded(null));

      await tester.pumpApp(
        BlocProvider<MyPharmacyCubit>.value(
          value: cubit,
          child: const MyPharmacyBody(),
        ),
      );

      expect(find.text('Aucune pharmacie déclarée'), findsOneWidget);
      expect(find.byKey(const Key('declare_pharmacy_button')), findsOneWidget);
    });

    testWidgets('pharmacie déclarée → carte + envoi d\'ordonnance',
        (tester) async {
      final cubit = MockMyPharmacyCubit();
      when(() => cubit.state).thenReturn(const MyPharmacyLoaded(pharmacy));

      await tester.pumpApp(
        BlocProvider<MyPharmacyCubit>.value(
          value: cubit,
          child: const MyPharmacyBody(),
        ),
      );

      expect(find.text('Pharmacie du Port'), findsOneWidget);
      expect(find.byKey(const Key('send_prescription_button')), findsOneWidget);
      expect(find.byKey(const Key('change_pharmacy_button')), findsOneWidget);
    });
  });
}
