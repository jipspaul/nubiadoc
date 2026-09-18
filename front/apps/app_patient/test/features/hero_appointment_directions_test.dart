import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/home/widgets/hero_appointment_card.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetDirectionsUseCase extends Mock implements GetDirectionsUseCase {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// #7304 : cabinet sans adresse TEXTE mais routable côté serveur (coordonnées
// GPS connues) — le bouton doit rester actif dans ce cas.
final _appt = Appointment(
  id: 'rdv-1',
  cabinetId: 'cab-dubois',
  practitionerName: 'Dr Amélie Dubois',
  practitionerSpecialty: 'Généraliste',
  startsAt: DateTime.now().add(const Duration(days: 1)),
  duration: const Duration(minutes: 30),
  motif: 'Contrôle',
  status: AppointmentStatus.confirmed,
  cabinetAddress: null,
);

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

  testWidgets(
      '#7304 : bouton Itinéraire actif sans adresse texte, tap appelle '
      '/directions avec id et mode car', (tester) async {
    when(
      () => mockGetDirections(
        id: any(named: 'id'),
        mode: any(named: 'mode'),
      ),
    ).thenAnswer(
      (_) async => const Right(DirectionsResult(deeplink: 'geo://48.8,2.3')),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HeroAppointmentCard(
            upcomingAppointments: 1,
            nextAppointment: _appt,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('hero_directions_button')));
    await tester.pump();

    verify(() => mockGetDirections(id: 'rdv-1', mode: 'car')).called(1);
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
      MaterialApp(
        home: Scaffold(
          body: HeroAppointmentCard(
            upcomingAppointments: 1,
            nextAppointment: _appt,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('hero_directions_button')));
    await tester.pumpAndSettle();

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });
}
