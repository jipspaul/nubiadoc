import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_page.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSearchProvidersUseCase extends Mock
    implements SearchProvidersUseCase {}

class MockSearchSlotsUseCase extends Mock implements SearchSlotsUseCase {}

class MockHoldSlotUseCase extends Mock implements HoldSlotUseCase {}

class MockConfirmBookingUseCase extends Mock implements ConfirmBookingUseCase {}

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(AppointmentsBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: AppointmentsPage()),
      ),
    );

AppointmentsBloc _makeBloc({
  required MockSearchProvidersUseCase searchProviders,
  required MockSearchSlotsUseCase searchSlots,
  required MockHoldSlotUseCase holdSlot,
  required MockConfirmBookingUseCase confirmBooking,
}) =>
    AppointmentsBloc(
      searchProviders: searchProviders,
      searchSlots: searchSlots,
      holdSlot: holdSlot,
      confirmBooking: confirmBooking,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockSearchProvidersUseCase mockSearchProviders;
  late MockSearchSlotsUseCase mockSearchSlots;
  late MockHoldSlotUseCase mockHoldSlot;
  late MockConfirmBookingUseCase mockConfirmBooking;

  setUp(() {
    mockSearchProviders = MockSearchProvidersUseCase();
    mockSearchSlots = MockSearchSlotsUseCase();
    mockHoldSlot = MockHoldSlotUseCase();
    mockConfirmBooking = MockConfirmBookingUseCase();
  });

  group('AppointmentsPage', () {
    testWidgets('affiche le champ de recherche en état initial',
        (tester) async {
      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        confirmBooking: mockConfirmBooking,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('search_field')), findsOneWidget);
    });

    testWidgets(
        'affiche "Aucun praticien trouvé." quand la recherche renvoie une liste vide',
        (tester) async {
      when(() => mockSearchProviders(query: any(named: 'query')))
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        searchProviders: mockSearchProviders,
        searchSlots: mockSearchSlots,
        holdSlot: mockHoldSlot,
        confirmBooking: mockConfirmBooking,
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
        confirmBooking: mockConfirmBooking,
      );

      bloc.add(const AppointmentsSearchChanged('dentiste'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Dr Dupont'), findsOneWidget);
    });
  });

  group('filtre local praticiens', () {
    late _MockAppointmentsBloc bloc;

    const providers = [
      ProviderResult(id: 'p1', displayName: 'Dr Martin', specialty: 'Dentiste'),
      ProviderResult(
          id: 'p2', displayName: 'Dr Dupont', specialty: 'Chirurgien'),
      ProviderResult(
          id: 'p3', displayName: 'Dr Bernard', specialty: 'Orthodontiste'),
    ];

    setUp(() {
      bloc = _MockAppointmentsBloc();
    });

    testWidgets('affiche la liste des praticiens chargés', (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(
            providers: providers, query: 'dentiste'),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      // Barre de recherche persistante + les 3 praticiens (ProviderCard).
      expect(find.byKey(const Key('search_field')), findsOneWidget);
      expect(find.byType(ProviderCard), findsNWidgets(3));
      expect(find.text('Dr Martin'), findsOneWidget);
    });

    testWidgets('affiche la carte plein écran + chips de filtres rapides',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(
            providers: providers, query: 'dentiste'),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      // Carte immersive + feuille de résultats + chips.
      expect(find.byKey(const Key('providers_map')), findsOneWidget);
      expect(find.byKey(const Key('providers_list')), findsOneWidget);
      expect(find.byKey(const Key('quick_filters')), findsOneWidget);
    });

    testWidgets(
        'tap sur une ProviderCard ouvre le détail « Voir les créneaux »',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AppointmentsProvidersLoaded(
            providers: providers, query: 'dentiste'),
      );
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: BlocProvider<AppointmentsBloc>.value(
          value: bloc,
          child: const Scaffold(body: AppointmentsPage()),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('provider_p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sheet_see_slots')), findsOneWidget);
      expect(find.text('Voir les créneaux'), findsOneWidget);
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
          confirmBooking: mockConfirmBooking,
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
      'query vide = annuaire par défaut (charge quand même des praticiens)',
      build: () {
        when(() => mockSearchProviders(query: any(named: 'query')))
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          searchProviders: mockSearchProviders,
          searchSlots: mockSearchSlots,
          holdSlot: mockHoldSlot,
          confirmBooking: mockConfirmBooking,
        );
      },
      act: (bloc) => bloc.add(const AppointmentsSearchChanged('')),
      expect: () => [
        const AppointmentsSearchLoading(),
        isA<AppointmentsProvidersLoaded>(),
      ],
      verify: (_) => verify(() => mockSearchProviders(query: '')).called(1),
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
          confirmBooking: mockConfirmBooking,
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
