import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/pickup_scan/pickup_scan_cubit.dart';
import 'package:app_pharmacie/features/pickup_scan/widgets/manual_code_field.dart';

class MockPharmacyOrdersRepository extends Mock
    implements PharmacyOrdersRepository {}

class MockPickupScanCubit extends MockCubit<PickupScanState>
    implements PickupScanCubit {}

PharmacyOrder pickedUp() => PharmacyOrder(
      id: 'o1',
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: PharmacyOrderStatus.pickedUp,
      createdAt: DateTime(2026, 7, 1, 10),
      updatedAt: DateTime(2026, 7, 1, 12),
    );

void main() {
  late MockPharmacyOrdersRepository repo;

  setUp(() => repo = MockPharmacyOrdersRepository());

  PickupScanCubit buildCubit() =>
      PickupScanCubit(confirmPickup: ConfirmPharmacyPickupUseCase(repo));

  group('PickupScanCubit', () {
    blocTest<PickupScanCubit, PickupScanState>(
      'code valide → Submitting puis Success',
      build: () {
        when(() => repo.confirmPickup('tok-1'))
            .thenAnswer((_) async => Right(pickedUp()));
        return buildCubit();
      },
      act: (cubit) => cubit.submit('  tok-1  '),
      expect: () => [
        const PickupScanSubmitting(),
        PickupScanSuccess(pickedUp()),
      ],
      verify: (_) => verify(() => repo.confirmPickup('tok-1')).called(1),
    );

    blocTest<PickupScanCubit, PickupScanState>(
      '409 (double scan) → InvalidCode',
      build: () {
        when(() => repo.confirmPickup(any())).thenAnswer(
          (_) async => const Left(ServerFailure(
              message: 'Action impossible.',
              statusCode: 409,
              code: 'invalid_status')),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.submit('tok-x'),
      expect: () =>
          [const PickupScanSubmitting(), isA<PickupScanInvalidCode>()],
    );

    blocTest<PickupScanCubit, PickupScanState>(
      '410 (token expiré) → InvalidCode',
      build: () {
        when(() => repo.confirmPickup(any())).thenAnswer(
          (_) async => const Left(ServerFailure(
              message: 'Code expiré.', statusCode: 410, code: 'token_expired')),
        );
        return buildCubit();
      },
      act: (cubit) => cubit.submit('tok-x'),
      expect: () =>
          [const PickupScanSubmitting(), isA<PickupScanInvalidCode>()],
    );

    blocTest<PickupScanCubit, PickupScanState>(
      'token inconnu (404) → InvalidCode ; erreur réseau → Error',
      build: () {
        when(() => repo.confirmPickup('inconnu'))
            .thenAnswer((_) async => const Left(NotFoundFailure()));
        when(() => repo.confirmPickup('reseau'))
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.submit('inconnu');
        await cubit.submit('reseau');
      },
      expect: () => [
        const PickupScanSubmitting(),
        isA<PickupScanInvalidCode>(),
        const PickupScanSubmitting(),
        isA<PickupScanError>(),
      ],
    );

    blocTest<PickupScanCubit, PickupScanState>(
      'code vide → aucun appel',
      build: buildCubit,
      act: (cubit) => cubit.submit('   '),
      expect: () => const <PickupScanState>[],
      verify: (_) => verifyNever(() => repo.confirmPickup(any())),
    );
  });

  group('ManualCodeField (widget)', () {
    testWidgets('toujours visible et soumet le code saisi', (tester) async {
      String? submitted;
      await tester.pumpApp(
        Scaffold(
          body: ManualCodeField(onSubmit: (code) => submitted = code),
        ),
      );

      await tester.enterText(
          find.byKey(const Key('manual_code_field')), 'abc123');
      await tester.tap(find.byKey(const Key('manual_code_submit')));

      expect(submitted, 'abc123');
    });

    testWidgets('désactivé pendant la soumission', (tester) async {
      var called = false;
      await tester.pumpApp(
        Scaffold(
          body: ManualCodeField(enabled: false, onSubmit: (_) => called = true),
        ),
      );
      await tester.tap(find.byKey(const Key('manual_code_submit')));
      expect(called, isFalse);
    });
  });
}
