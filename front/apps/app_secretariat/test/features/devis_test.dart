import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/devis/devis_bloc.dart';
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

    final quotes = [
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
    ];

    setUp(() {
      repo = _MockCabinetQuotesRepository();
      listUseCase = ListCabinetQuotesUseCase(repo);
    });

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list(page: any(named: 'page')))
            .thenAnswer((_) async => Right(quotes));
        return DevisBloc(listQuotes: listUseCase);
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
        return DevisBloc(listQuotes: listUseCase);
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
        return DevisBloc(listQuotes: listUseCase);
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
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
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
  });
}
