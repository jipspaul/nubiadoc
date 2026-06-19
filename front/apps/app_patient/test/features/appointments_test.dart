import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_page.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSearchProvidersUseCase extends Mock implements SearchProvidersUseCase {}
class MockSearchSlotsUseCase extends Mock implements SearchSlotsUseCase {}
class MockHoldSlotUseCase extends Mock implements HoldSlotUseCase {}
class MockBookAppointmentUseCase extends Mock implements BookAppointmentUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(AppointmentsBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: AppointmentsPage()),
      ),
    );

AppointmentsBloc _makeBloc({
  required MockSearchProvidersUseCase searchProviders,
  required MockSearchSlotsUseCase searchSlots,
  required MockHoldSlotUseCase holdSlot,
  required MockBookAppointmentUseCase bookAppointment,
}) =>
    AppointmentsBloc(
      searchProviders: searchProviders,
      searchSlots: searchSlots,
      holdSlot: holdSlot,
      bookAppointment: bookAppointment,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockSearchProvidersUseCase mockSearchProviders;
  late MockSearchSlotsUseCase mockSearchSlots;
  late MockHoldSlotUseCase mockHoldSlot;
  late MockBookAppointmentUseCase mockBookAppointment;

  setUp(() {
    mockSearchProviders = MockSearchProvidersUseCase();
    mockSearchSlots = MockSearchSlotsUseCase();
    mockHoldSlot = MockHoldSlotUseCase();
    mockBookAppointment = MockBookAppointmentUseCase();
  });

  group('AppointmentsPage', () {
    testWidgets('affiche le champ de recherche en état initial', (tester) async {
      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        bookAppointment: mockBookAppointment,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('search_field')), findsOneWidget);
    });

    testWidgets('affiche "Aucun praticien trouvé." quand la recherche renvoie une liste vide',
        (tester) async {
      when(() => mockSearchProviders(query: any(named: 'query')))
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        bookAppointment: mockBookAppointment,
      );

      bloc.add(const AppointmentsSearchChanged('dentiste'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_providers')), findsOneWidget);
    });

    testWidgets('affiche la liste des praticiens quand la recherche réussit',
        (tester) async {
      const provider = ProviderResult(
        id: 'prov-1',
        displayName: 'Dr Dupont',
        specialty: 'Dentiste',
      );
      when(() => mockSearchProviders(query: any(named: 'query')))
          .thenAnswer((_) async => const Right([provider]));

      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        bookAppointment: mockBookAppointment,
      );

      bloc.add(const AppointmentsSearchChanged('dentiste'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Dr Dupont'), findsOneWidget);
    });
  });

  group('AppointmentsBloc', () {
    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet [SearchLoading, ProvidersLoaded(empty)] quand la recherche renvoie []',
      build: () {
        when(() => mockSearchProviders(query: any(named: 'query')))
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          bookAppointment: mockBookAppointment,
        );
      },
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('ortho')),
      expect: () => [
        const AppointmentsSearchLoading(),
        isA<AppointmentsProvidersLoaded>()
            .having((s) => s.providers, 'providers', isEmpty),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet [Initial] quand la query est vide',
      build: () => _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        bookAppointment: mockBookAppointment,
      ),
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('')),
      expect: () => [const AppointmentsInitial()],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet [Error] quand la recherche échoue',
      build: () {
        when(() => mockSearchProviders(query: any(named: 'query'))).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          bookAppointment: mockBookAppointment,
        );
      },
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('dentiste')),
      expect: () => [
        const AppointmentsSearchLoading(),
        isA<AppointmentsError>(),
      ],
    );
  });
}
