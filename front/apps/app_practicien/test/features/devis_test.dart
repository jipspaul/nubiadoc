import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/devis/devis_bloc.dart';
import 'package:app_practicien/features/devis/devis_event.dart';
import 'package:app_practicien/features/devis/devis_page.dart';
import 'package:app_practicien/features/devis/devis_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListCabinetQuotesUseCase extends Mock
    implements ListCabinetQuotesUseCase {}

class MockGetCabinetQuoteUseCase extends Mock
    implements GetCabinetQuoteUseCase {}

class MockDevisBloc extends MockBloc<DevisEvent, DevisState>
    implements DevisBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _line = QuoteLineItem(
  id: 'l1',
  label: 'Couronne céramique',
  ccamCode: 'HBLD038',
  toothLabel: '26',
  totalCents: 60000,
  amoShareCents: 8400,
  amcShareCents: 20000,
  patientShareCents: 31600,
);

final _draftQuote = CabinetQuote(
  id: 'q1',
  cabinetId: 'cab-1',
  patientId: 'pat-1',
  patientName: 'Jean Dupont',
  totalCents: 60000,
  patientShareCents: 31600,
  status: CabinetQuoteStatus.draft,
  createdAt: DateTime(2026, 6, 20),
  items: const [_line],
);

final _sentQuote = CabinetQuote(
  id: 'q2',
  cabinetId: 'cab-1',
  patientId: 'pat-2',
  patientName: 'Marie Martin',
  totalCents: 120000,
  patientShareCents: 50000,
  status: CabinetQuoteStatus.sent,
  createdAt: DateTime(2026, 6, 21),
);

DevisBloc _makeBloc({
  required MockListCabinetQuotesUseCase list,
  required MockGetCabinetQuoteUseCase getById,
}) =>
    DevisBloc(list: list, getById: getById);

Widget _wrap(DevisBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<DevisBloc>.value(
          value: bloc,
          child: const DevisBody(),
        ),
      ),
    );

// ---------------------------------------------------------------------------

void main() {
  late MockListCabinetQuotesUseCase mockList;
  late MockGetCabinetQuoteUseCase mockGet;

  setUp(() {
    mockList = MockListCabinetQuotesUseCase();
    mockGet = MockGetCabinetQuoteUseCase();
  });

  group('DevisBloc', () {
    blocTest<DevisBloc, DevisState>(
      'émet Loading puis ListLoaded après chargement réussi',
      build: () {
        when(() => mockList(page: any(named: 'page')))
            .thenAnswer((_) async => Right([_draftQuote, _sentQuote]));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisListRequested()),
      expect: () => [
        const DevisLoading(),
        DevisListLoaded([_draftQuote, _sentQuote]),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis Error si le chargement échoue',
      build: () {
        when(() => mockList(page: any(named: 'page')))
            .thenAnswer((_) async => Left(NetworkFailure('Pas de réseau')));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisListRequested()),
      expect: () => [
        const DevisLoading(),
        const DevisError('Pas de réseau'),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis DetailLoaded à la sélection d\'un devis',
      build: () {
        when(() => mockGet(any())).thenAnswer((_) async => Right(_draftQuote));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisQuoteSelected('q1')),
      expect: () => [
        const DevisLoading(),
        DevisDetailLoaded(_draftQuote),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet SendInProgress puis Sent à l\'envoi d\'un brouillon',
      build: () => _makeBloc(list: mockList, getById: mockGet),
      seed: () => DevisDetailLoaded(_draftQuote),
      act: (bloc) => bloc.add(const DevisSendRequested('q1')),
      expect: () => [
        DevisSendInProgress(_draftQuote),
        isA<DevisSent>(),
      ],
    );
  });

  group('DevisBody (widget)', () {
    testWidgets('affiche le skeleton en chargement', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(const DevisLoading());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste des devis', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state)
          .thenReturn(DevisListLoaded([_draftQuote, _sentQuote]));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_list')), findsOneWidget);
      expect(find.byKey(const Key('devis_item_q1')), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);
    });

    testWidgets('affiche l\'état vide', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(const DevisListLoaded([]));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_empty')), findsOneWidget);
    });

    testWidgets('affiche l\'erreur avec retry', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(const DevisError('Boom'));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_error')), findsOneWidget);
    });

    testWidgets('affiche le détail avec CTA Envoyer pour un brouillon',
        (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_detail')), findsOneWidget);
      expect(find.byType(AmountHeader), findsOneWidget);
      expect(find.byType(QuoteCard), findsOneWidget);
      expect(find.byKey(const Key('btn_send_devis')), findsOneWidget);
    });

    testWidgets('masque le CTA Envoyer pour un devis déjà envoyé',
        (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_sentQuote));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_detail')), findsOneWidget);
      expect(find.byKey(const Key('btn_send_devis')), findsNothing);
    });

    testWidgets('le CTA Envoyer dispatch DevisSendRequested', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.tap(find.byKey(const Key('btn_send_devis')));
      verify(() => bloc.add(const DevisSendRequested('q1'))).called(1);
    });

    testWidgets('affiche la confirmation d\'envoi', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisSent(_sentQuote));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_sent')), findsOneWidget);
    });
  });
}
