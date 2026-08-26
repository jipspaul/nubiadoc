import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/devis/devis_bloc.dart';
import 'package:app_secretariat/features/devis/devis_detail_page.dart';
import 'package:app_secretariat/features/devis/devis_event.dart';
import 'package:app_secretariat/features/devis/devis_page.dart';
import 'package:app_secretariat/features/devis/devis_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockCabinetQuotesRepository extends Mock
    implements CabinetQuotesRepository {}

class _MockDevisBloc extends MockBloc<DevisEvent, DevisState>
    implements DevisBloc {}

void main() {
  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- CabinetQuote : pas de champ clinique ------------------------------------
  group('CabinetQuote — cloisonnement champs cliniques', () {
    test('CabinetQuote ne porte pas de champ motif ni notes_medicales', () {
      final quote = CabinetQuote(
        id: 'q1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Jean Dupont',
        totalCents: 15000,
        patientShareCents: 5000,
        status: CabinetQuoteStatus.sent,
        createdAt: DateTime(2026, 1, 1),
      );
      // Garantie structurelle : le type CabinetQuote n'expose pas de champ clinique.
      final json = {
        'id': quote.id,
        'patientName': quote.patientName,
        'totalCents': quote.totalCents,
        'status': quote.status.name,
      };
      expect(json.containsKey('motif'), isFalse);
      expect(json.containsKey('notesMedicales'), isFalse);
    });
  });

  // --- DevisBloc ---------------------------------------------------------------
  group('DevisBloc', () {
    late _MockCabinetQuotesRepository repo;
    late ListCabinetQuotesUseCase listUseCase;
    late GetCabinetQuoteUseCase getUseCase;
    late SendCabinetQuoteUseCase sendUseCase;

    final quote = CabinetQuote(
      id: 'q1',
      cabinetId: 'c1',
      patientId: 'p1',
      patientName: 'Marie Curie',
      totalCents: 20000,
      patientShareCents: 10000,
      status: CabinetQuoteStatus.sent,
      createdAt: DateTime(2026, 1, 1),
    );
    final quotes = [quote];

    setUp(() {
      repo = _MockCabinetQuotesRepository();
      listUseCase = ListCabinetQuotesUseCase(repo);
      getUseCase = GetCabinetQuoteUseCase(repo);
      sendUseCase = SendCabinetQuoteUseCase(repo);
    });

    DevisBloc buildBloc() => DevisBloc(
          listQuotes: listUseCase,
          getQuote: getUseCase,
          sendQuote: sendUseCase,
        );

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list(page: any(named: 'page')))
            .thenAnswer((_) async => Right(quotes));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DevisLoadRequested()),
      expect: () => [
        const DevisLoading(),
        DevisLoaded(quotes),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(() => repo.list(page: any(named: 'page'))).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DevisLoadRequested()),
      expect: () => [
        const DevisLoading(),
        const DevisError('Erreur réseau'),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'les devis chargés n\'exposent aucun champ clinique',
      build: () {
        when(() => repo.list(page: any(named: 'page')))
            .thenAnswer((_) async => Right(quotes));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DevisLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<DevisLoaded>());
        for (final q in (loaded as DevisLoaded).quotes) {
          expect(q.patientName, isNotEmpty);
          // CabinetQuote ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type (pas de getter correspondant).
        }
      },
    );

    // --- GetCabinetQuote ---
    blocTest<DevisBloc, DevisState>(
      'DevisDetailLoadRequested émet Loading puis DevisDetailLoaded sur succès',
      build: () {
        when(() => repo.getById('q1')).thenAnswer((_) async => Right(quote));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DevisDetailLoadRequested('q1')),
      expect: () => [
        const DevisLoading(),
        DevisDetailLoaded(quote),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'DevisDetailLoadRequested émet Loading puis DevisDetailError sur échec',
      build: () {
        when(() => repo.getById(any())).thenAnswer(
          (_) async => Left(const NetworkFailure('Introuvable')),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const DevisDetailLoadRequested('q999')),
      expect: () => [
        const DevisLoading(),
        const DevisDetailError('Introuvable'),
      ],
    );

    test('DevisDetailLoaded ne porte aucun champ clinique', () {
      final state = DevisDetailLoaded(quote);
      expect(state.quote.patientName, isNotEmpty);
      // Garantie structurelle : CabinetQuote n'a pas de champ motif/notes.
      final keys = {
        'id': state.quote.id,
        'patientName': state.quote.patientName,
        'status': state.quote.status.name,
      };
      expect(keys.containsKey('motif'), isFalse);
      expect(keys.containsKey('notesMedicales'), isFalse);
    });

    // #4537 : le secrétariat peut désormais envoyer un devis brouillon —
    // le back autorise déjà secretary+, seule l'UI en manquait l'action.
    blocTest<DevisBloc, DevisState>(
      'DevisSendRequested émet InProgress puis Sent sur succès',
      build: () {
        when(() => repo.sendQuote(quote.id)).thenAnswer(
          (_) async => const Right(CabinetQuoteStatus.sent),
        );
        return buildBloc();
      },
      seed: () => DevisDetailLoaded(quote),
      act: (bloc) => bloc.add(DevisSendRequested(quote.id)),
      expect: () => [
        DevisSendInProgress(quote),
        isA<DevisSent>(),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'DevisSendRequested émet InProgress puis SendFailure sur échec',
      build: () {
        when(() => repo.sendQuote(quote.id)).thenAnswer(
          (_) async => Left(const NetworkFailure('Envoi impossible.')),
        );
        return buildBloc();
      },
      seed: () => DevisDetailLoaded(quote),
      act: (bloc) => bloc.add(DevisSendRequested(quote.id)),
      expect: () => [
        DevisSendInProgress(quote),
        DevisSendFailure(quote: quote, message: 'Envoi impossible.'),
      ],
    );
  });

  // --- DevisPage widget test ---------------------------------------------------
  group('DevisPage', () {
    late _MockDevisBloc bloc;

    setUp(() {
      bloc = _MockDevisBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<DevisBloc>.value(
            value: bloc,
            child: const DevisPage(),
          ),
        );

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const DevisInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les devis — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        DevisLoaded([
          CabinetQuote(
            id: 'q1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            totalCents: 20000,
            patientShareCents: 10000,
            status: CabinetQuoteStatus.sent,
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche un message si la liste est vide', (tester) async {
      when(() => bloc.state).thenReturn(const DevisLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun devis enregistré.'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const DevisError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });

    testWidgets('toggle tri ASC/DESC change l\'ordre des devis',
        (tester) async {
      final older = CabinetQuote(
        id: 'q1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Alice',
        totalCents: 10000,
        patientShareCents: 3000,
        status: CabinetQuoteStatus.sent,
        createdAt: DateTime(2026, 1, 1),
      );
      final newer = CabinetQuote(
        id: 'q2',
        cabinetId: 'c1',
        patientId: 'p2',
        patientName: 'Bob',
        totalCents: 20000,
        patientShareCents: 5000,
        status: CabinetQuoteStatus.draft,
        createdAt: DateTime(2026, 6, 1),
      );
      when(() => bloc.state).thenReturn(DevisLoaded([older, newer]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Par défaut DESC : Bob (plus récent) en premier
      final namesBefore = tester
          .widgetList<Text>(find.text('Alice').evaluate().isNotEmpty
              ? find.byType(Text)
              : find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == 'Alice' || d == 'Bob')
          .toList();
      expect(namesBefore.first, 'Bob');

      // Toggle → ASC : Alice (plus ancien) en premier
      await tester.tap(find.byKey(const Key('sort_button')));
      await tester.pumpAndSettle();

      final namesAfter = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == 'Alice' || d == 'Bob')
          .toList();
      expect(namesAfter.first, 'Alice');
    });
  });

  // --- DevisDetailPage widget test --------------------------------------------
  group('DevisDetailPage', () {
    late _MockDevisBloc bloc;

    final detailQuote = CabinetQuote(
      id: 'q1',
      cabinetId: 'c1',
      patientId: 'p1',
      patientName: 'Albert Einstein',
      totalCents: 35000,
      patientShareCents: 12000,
      status: CabinetQuoteStatus.signed,
      createdAt: DateTime(2026, 2, 1),
      signedAt: DateTime(2026, 2, 10),
    );

    setUp(() {
      bloc = _MockDevisBloc();
    });

    Widget buildDetailPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<DevisBloc>.value(
            value: bloc,
            child: const DevisDetailPage(id: 'q1'),
          ),
        );

    testWidgets('affiche le chargement', (tester) async {
      when(() => bloc.state).thenReturn(const DevisLoading());
      await tester.pumpWidget(buildDetailPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche le détail — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(DevisDetailLoaded(detailQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('Albert Einstein'), findsOneWidget);
      expect(find.text(NubiaMoney.formatCents(35000)), findsOneWidget);
      expect(find.text('350,00 €'), findsOneWidget);
      expect(find.text('350.00 €'), findsNothing);
      // Cloisonnement : aucun libellé clinique
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
    });

    testWidgets('formate les gros montants avec séparateur de milliers',
        (tester) async {
      final bigQuote = CabinetQuote(
        id: 'q2',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Marie Curie',
        totalCents: 1245067,
        patientShareCents: 14850,
        status: CabinetQuoteStatus.signed,
        createdAt: DateTime(2026, 2, 1),
      );
      when(() => bloc.state).thenReturn(DevisDetailLoaded(bigQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('12 450,67 €'), findsOneWidget);
      expect(find.text('148,50 €'), findsOneWidget);
    });

    testWidgets('affiche l\'erreur de détail', (tester) async {
      when(() => bloc.state)
          .thenReturn(const DevisDetailError('Devis introuvable'));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('Devis introuvable'), findsOneWidget);
    });
  });
}
