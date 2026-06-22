import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/detail_rdv_page.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetDirectionsUseCase extends Mock implements GetDirectionsUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _appt = Appointment(
  id: 'rdv-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  practitionerSpecialty: 'Dentiste',
  startsAt: DateTime(2026, 8, 15, 10, 0),
  duration: const Duration(minutes: 30),
  motif: 'Détartrage',
  status: AppointmentStatus.confirmed,
  cabinetAddress: '12 rue de la Paix, Paris',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetDirectionsUseCase mockGetDirections;

  setUpAll(() {
    registerFallbackValue(const DirectionsResult(deeplink: 'geo://0,0'));
  });

  setUp(() async {
    mockGetDirections = MockGetDirectionsUseCase();
    await GetIt.instance.reset();
    GetIt.instance
        .registerFactory<GetDirectionsUseCase>(() => mockGetDirections);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets('tap déclenche getDirections avec id et mode car',
      (tester) async {
    when(
      () => mockGetDirections(
        id: any(named: 'id'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer(
      (_) async => const Right(DirectionsResult(deeplink: 'geo://48.8,2.3')),
    );

    await tester.pumpWidget(
      MaterialApp(home: DetailRdvPage(appointment: _appt)),
    );

    await tester.tap(find.byKey(const Key('directions_button')));
    await tester.pump();

    verify(
      () => mockGetDirections(id: 'rdv-1', mode: 'car'),
    ).called(1);
  });

  testWidgets('erreur Failure affiche un snackbar', (tester) async {
    when(
      () => mockGetDirections(
        id: any(named: 'id'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer(
      (_) async => const Left(NetworkFailure('Erreur réseau.')),
    );

    await tester.pumpWidget(
      MaterialApp(home: DetailRdvPage(appointment: _appt)),
    );

    await tester.tap(find.byKey(const Key('directions_button')));
    await tester.pumpAndSettle();

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });
}
