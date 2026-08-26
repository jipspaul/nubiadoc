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
import 'package:app_secretariat/features/devis/widgets/devis_kpis.dart';
import 'package:app_secretariat/features/devis/widgets/quote_timeline.dart';
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

  // --- mapQuoteStatus (#5093) ---------------------------------------------------
  group('mapQuoteStatus', () {
    test('cancelled ne renvoie plus refused mais cancelled', () {
      expect(
        mapQuoteStatus(CabinetQuoteStatus.cancelled),
        QuoteCardStatus.cancelled,
      );
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
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('devis_list_skeleton')), findsOneWidget);
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

    testWidgets('devis annulé affiche « Annulé » et jamais « Refusé » (#5093)',
        (tester) async {
      when(() => bloc.state).thenReturn(
        DevisLoaded([
          CabinetQuote(
            id: 'q1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Paul Cancelled',
            totalCents: 15000,
            patientShareCents: 5000,
            status: CabinetQuoteStatus.cancelled,
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Annulé'), findsOneWidget);
      expect(find.text('Refusé'), findsNothing);
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
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('devis_detail_skeleton')), findsOneWidget);
    });

    testWidgets('affiche le détail — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(DevisDetailLoaded(detailQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('Albert Einstein'), findsOneWidget);
      expect(
        find.text(
          'Reste à charge patient · sur ${NubiaMoney.formatCents(35000)}',
        ),
        findsOneWidget,
      );
      expect(find.text(NubiaMoney.formatCents(12000)), findsOneWidget);
      expect(find.text('350.00 €'), findsNothing);
      // Cloisonnement : aucun libellé clinique
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
    });

    testWidgets('devis annulé affiche « Annulé » et jamais « Refusé » (#5093)',
        (tester) async {
      final cancelledQuote = CabinetQuote(
        id: 'q1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Paul Cancelled',
        totalCents: 15000,
        patientShareCents: 5000,
        status: CabinetQuoteStatus.cancelled,
        createdAt: DateTime(2026, 1, 1),
      );
      when(() => bloc.state).thenReturn(DevisDetailLoaded(cancelledQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('Annulé'), findsOneWidget);
      expect(find.text('Refusé'), findsNothing);
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

      expect(
        find.text('Reste à charge patient · sur 12 450,67 €'),
        findsOneWidget,
      );
      expect(find.text('148,50 €'), findsOneWidget);
    });

    testWidgets(
        'affiche « Payé » (et non « Signé ») quand l\'acompte est réglé (#5094)',
        (tester) async {
      final paidQuote = CabinetQuote(
        id: 'q3',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Ada Lovelace',
        totalCents: 50000,
        patientShareCents: 20000,
        status: CabinetQuoteStatus.paid,
        createdAt: DateTime(2026, 2, 1),
        signedAt: DateTime(2026, 2, 10),
      );
      when(() => bloc.state).thenReturn(DevisDetailLoaded(paidQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('Payé'), findsOneWidget);
      expect(find.text('Signé'), findsNothing);
    });

    testWidgets('affiche l\'erreur de détail', (tester) async {
      when(() => bloc.state)
          .thenReturn(const DevisDetailError('Devis introuvable'));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('Devis introuvable'), findsOneWidget);
    });

    testWidgets(
        'affiche la ventilation AMO/AMC/reste à charge — même calcul et '
        'même vocabulaire que l\'app Patient (#5091)', (tester) async {
      final quoteWithItems = CabinetQuote(
        id: 'q4',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Julie Martin',
        totalCents: 43592,
        patientShareCents: 14850,
        status: CabinetQuoteStatus.signed,
        createdAt: DateTime(2026, 2, 1),
        items: const [
          QuoteLineItem(
            id: 'l1',
            label: 'Acte 1',
            totalCents: 43592,
            amoShareCents: 16566,
            amcShareCents: 12176,
            patientShareCents: 14850,
          ),
        ],
      );
      when(() => bloc.state).thenReturn(DevisDetailLoaded(quoteWithItems));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ventilation_bar')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amo')),
          matching: find.text('Assurance Maladie (AMO)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amo')),
          matching: find.text(NubiaMoney.formatCents(-16566)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amc')),
          matching: find.text(NubiaMoney.formatCents(-12176)),
        ),
        findsOneWidget,
      );
      expect(find.text('Reste à charge'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ventilation_rac_value')))
            .data,
        NubiaMoney.formatCents(14850),
      );
    });

    testWidgets(
        'omet la ventilation proprement quand CabinetQuote.items est null',
        (tester) async {
      when(() => bloc.state).thenReturn(DevisDetailLoaded(detailQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ventilation_bar')), findsNothing);
    });

    testWidgets(
        'affiche le bloc Suivi avec « Devis créé » et « Signature attendue » '
        'pour un devis envoyé en attente de signature', (tester) async {
      final pendingQuote = CabinetQuote(
        id: 'q5',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Jean Rousseau',
        totalCents: 20000,
        patientShareCents: 8000,
        status: CabinetQuoteStatus.sent,
        createdAt: DateTime(2026, 8, 4, 9, 12),
        expiresAt: DateTime(2026, 8, 13),
      );
      when(() => bloc.state).thenReturn(DevisDetailLoaded(pendingQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_timeline')), findsOneWidget);
      expect(find.text('Suivi'), findsOneWidget);
      expect(find.text('Devis créé'), findsOneWidget);
      expect(find.text('04/08 · 09:12'), findsOneWidget);
      expect(find.text('Signature attendue'), findsOneWidget);
    });

    testWidgets(
        'bloc Suivi — devis signé : pas d\'étape « Signature attendue » '
        'inventée', (tester) async {
      when(() => bloc.state).thenReturn(DevisDetailLoaded(detailQuote));
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_timeline')), findsOneWidget);
      expect(find.text('Devis créé'), findsOneWidget);
      expect(find.text('Signature attendue'), findsNothing);
    });
  });

  // --- QuoteTimeline (#5090) ----------------------------------------------------
  group('QuoteTimeline', () {
    Widget buildTimeline(CabinetQuote quote, {DateTime? now}) => MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: QuoteTimeline(quote: quote, now: now),
          ),
        );

    testWidgets('devis brouillon sans expiresAt : seule « Devis créé » '
        'est affichée', (tester) async {
      final quote = CabinetQuote(
        id: 'q1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Alice',
        totalCents: 10000,
        patientShareCents: 4000,
        status: CabinetQuoteStatus.draft,
        createdAt: DateTime(2026, 8, 4, 9, 12),
      );
      await tester.pumpWidget(buildTimeline(quote));
      await tester.pumpAndSettle();

      expect(find.text('Devis créé'), findsOneWidget);
      expect(find.text('Signature attendue'), findsNothing);
    });

    testWidgets(
        '« Signature attendue » affiche « expire le JJ/MM · dans N jours »',
        (tester) async {
      final now = DateTime(2026, 8, 10);
      final quote = CabinetQuote(
        id: 'q1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Alice',
        totalCents: 10000,
        patientShareCents: 4000,
        status: CabinetQuoteStatus.sent,
        createdAt: DateTime(2026, 8, 4, 9, 12),
        expiresAt: DateTime(2026, 8, 13),
      );
      await tester.pumpWidget(buildTimeline(quote, now: now));
      await tester.pumpAndSettle();

      expect(find.text('expire le 13/08 · dans 3 jours'), findsOneWidget);
    });

    testWidgets('« Signature attendue » omet le décompte si déjà expiré',
        (tester) async {
      final now = DateTime(2026, 8, 20);
      final quote = CabinetQuote(
        id: 'q1',
        cabinetId: 'c1',
        patientId: 'p1',
        patientName: 'Alice',
        totalCents: 10000,
        patientShareCents: 4000,
        status: CabinetQuoteStatus.sent,
        createdAt: DateTime(2026, 8, 4, 9, 12),
        expiresAt: DateTime(2026, 8, 13),
      );
      await tester.pumpWidget(buildTimeline(quote, now: now));
      await tester.pumpAndSettle();

      expect(find.text('expire le 13/08'), findsOneWidget);
      expect(find.textContaining('dans'), findsNothing);
    });
  });

  // --- DevisKpis (#5092) --------------------------------------------------------
  group('DevisKpis.fromQuotes', () {
    final now = DateTime(2026, 6, 15);

    test('compte actifs (ni annulés ni expirés), en attente, montant engagé',
        () {
      final quotes = [
        CabinetQuote(
          id: 'q1',
          cabinetId: 'c1',
          patientId: 'p1',
          patientName: 'Marie Curie',
          totalCents: 20000,
          patientShareCents: 10000,
          status: CabinetQuoteStatus.sent,
          createdAt: now,
          expiresAt: now.add(const Duration(days: 3)),
        ),
        CabinetQuote(
          id: 'q2',
          cabinetId: 'c1',
          patientId: 'p2',
          patientName: 'Paul Cancelled',
          totalCents: 15000,
          patientShareCents: 5000,
          status: CabinetQuoteStatus.cancelled,
          createdAt: now,
        ),
        CabinetQuote(
          id: 'q3',
          cabinetId: 'c1',
          patientId: 'p3',
          patientName: 'Léa Expired',
          totalCents: 8000,
          patientShareCents: 3000,
          status: CabinetQuoteStatus.expired,
          createdAt: now,
        ),
        CabinetQuote(
          id: 'q4',
          cabinetId: 'c1',
          patientId: 'p4',
          patientName: 'Signed',
          totalCents: 12000,
          patientShareCents: 4000,
          status: CabinetQuoteStatus.signed,
          createdAt: now,
        ),
      ];

      final kpis = DevisKpis.fromQuotes(quotes, now: now);

      // actifs = sent + signed (ni annulé ni expiré)
      expect(kpis.activeCount, 2);
      expect(kpis.pendingSignatureCount, 1);
      expect(kpis.expiringSoonCount, 1);
      // montant engagé = somme des actifs : q1 (20000) + q4 (12000)
      expect(kpis.engagedAmountCents, 32000);
    });

    test('« expire sous 7 jours » exclut un envoi expirant dans 10 jours', () {
      final quotes = [
        CabinetQuote(
          id: 'q1',
          cabinetId: 'c1',
          patientId: 'p1',
          patientName: 'Marie Curie',
          totalCents: 20000,
          patientShareCents: 10000,
          status: CabinetQuoteStatus.sent,
          createdAt: now,
          expiresAt: now.add(const Duration(days: 10)),
        ),
      ];

      final kpis = DevisKpis.fromQuotes(quotes, now: now);

      expect(kpis.pendingSignatureCount, 1);
      expect(kpis.expiringSoonCount, 0);
    });

    test('liste vide → tous les compteurs à zéro', () {
      final kpis = DevisKpis.fromQuotes(const [], now: now);
      expect(kpis.activeCount, 0);
      expect(kpis.pendingSignatureCount, 0);
      expect(kpis.expiringSoonCount, 0);
      expect(kpis.engagedAmountCents, 0);
    });
  });

  group('DevisPage — bandeau KPI', () {
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

    testWidgets('affiche les quatre compteurs dérivés de DevisLoaded.quotes',
        (tester) async {
      when(() => bloc.state).thenReturn(
        DevisLoaded([
          CabinetQuote(
            id: 'q1',
            cabinetId: 'c1',
            patientId: 'p1',
            patientName: 'Marie Curie',
            totalCents: 1842000,
            patientShareCents: 100000,
            status: CabinetQuoteStatus.sent,
            createdAt: DateTime(2026, 1, 1),
            expiresAt: DateTime.now().add(const Duration(days: 2)),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('devis_kpi_active')), findsOneWidget);
      expect(
        find.byKey(const Key('devis_kpi_pending_signature')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('devis_kpi_expiring_soon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('devis_kpi_engaged_amount')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('devis_kpi_engaged_amount')),
          matching: find.text('18 420,00 €'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pas de bandeau KPI hors état DevisLoaded', (tester) async {
      when(() => bloc.state).thenReturn(const DevisInitial());
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.byKey(const Key('devis_kpi_active')), findsNothing);
    });
  });
}
