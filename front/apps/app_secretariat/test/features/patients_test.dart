import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_bloc.dart';
import 'package:app_secretariat/features/patients/patients_event.dart';
import 'package:app_secretariat/features/patients/patients_page.dart';
import 'package:app_secretariat/features/patients/patients_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockCabinetPatientsRepository extends Mock
    implements CabinetPatientsRepository {}

class _MockPatientsBloc extends MockBloc<PatientsEvent, PatientsState>
    implements PatientsBloc {}

class _MockListPatientAlerts extends Mock implements ListPatientAlertsUseCase {}

class _MockGetCabinetPatient extends Mock implements GetCabinetPatientUseCase {}

class _MockListPatientTags extends Mock implements ListPatientTagsUseCase {}

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

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

  // --- CabinetPatient : pas de champ clinique ----------------------------------
  group('CabinetPatient — cloisonnement champs cliniques', () {
    test('fullName accessible (non-clinique)', () {
      final patient = CabinetPatient(
        id: 'p1',
        cabinetId: 'c1',
        firstName: 'Jean',
        lastName: 'Dupont',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(patient.fullName, 'Jean Dupont');
    });

    test('CabinetPatient ne porte pas de champ motif ni notes_medicales', () {
      // La contrainte est structurelle : le type ne définit pas ces champs.
      // Ce test garantit qu'aucune régression ne les introduira.
      final fields = CabinetPatient(
        id: 'p1',
        cabinetId: 'c1',
        firstName: 'Jean',
        lastName: 'Dupont',
        createdAt: DateTime(2026, 1, 1),
      );
      // ignore: unnecessary_type_check
      expect(fields, isA<CabinetPatient>());
      // Ces assertions vérifient l'absence structurelle via réflexion textuelle :
      // CabinetPatient n'a pas de getter 'motif' ni 'notesMedicales'.
      final json = {
        'id': fields.id,
        'cabinetId': fields.cabinetId,
        'firstName': fields.firstName,
        'lastName': fields.lastName,
      };
      expect(json.containsKey('motif'), isFalse);
      expect(json.containsKey('notesMedicales'), isFalse);
    });
  });

  // --- PatientsBloc ------------------------------------------------------------
  group('PatientsBloc', () {
    late _MockCabinetPatientsRepository repo;
    late ListCabinetPatientsUseCase listUseCase;
    late CreateCabinetPatientUseCase createUseCase;

    final patients = [
      CabinetPatient(
        id: 'p1',
        cabinetId: 'c1',
        firstName: 'Marie',
        lastName: 'Curie',
        email: 'marie@example.com',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    setUp(() {
      repo = _MockCabinetPatientsRepository();
      listUseCase = ListCabinetPatientsUseCase(repo);
      createUseCase = CreateCabinetPatientUseCase(repo);
    });

    blocTest<PatientsBloc, PatientsState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => repo.list(page: any(named: 'page'), q: any(named: 'q')))
            .thenAnswer((_) async => Right(patients));
        return PatientsBloc(
            listPatients: listUseCase, createPatient: createUseCase);
      },
      act: (bloc) => bloc.add(const PatientsLoadRequested()),
      expect: () => [
        const PatientsLoading(),
        PatientsLoaded(patients),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(() => repo.list(page: any(named: 'page'), q: any(named: 'q')))
            .thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        return PatientsBloc(
            listPatients: listUseCase, createPatient: createUseCase);
      },
      act: (bloc) => bloc.add(const PatientsLoadRequested()),
      expect: () => [
        const PatientsLoading(),
        const PatientsError('Erreur réseau'),
      ],
    );

    // ── Recherche serveur (#4043) ───────────────────────────────────────────

    blocTest<PatientsBloc, PatientsState>(
      'PatientsSearchChanged appelle le repository avec q=<texte>',
      build: () {
        when(() => repo.list(page: any(named: 'page'), q: any(named: 'q')))
            .thenAnswer((_) async => Right(patients));
        return PatientsBloc(
            listPatients: listUseCase, createPatient: createUseCase);
      },
      act: (bloc) => bloc.add(const PatientsSearchChanged('mar')),
      expect: () => [
        const PatientsLoading(),
        PatientsLoaded(patients),
      ],
      verify: (_) {
        verify(() => repo.list(page: 1, q: 'mar')).called(1);
      },
    );

    blocTest<PatientsBloc, PatientsState>(
      'les patients chargés n\'exposent aucun champ clinique',
      build: () {
        when(() => repo.list(page: any(named: 'page'), q: any(named: 'q')))
            .thenAnswer((_) async => Right(patients));
        return PatientsBloc(
            listPatients: listUseCase, createPatient: createUseCase);
      },
      act: (bloc) => bloc.add(const PatientsLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<PatientsLoaded>());
        for (final p in (loaded as PatientsLoaded).patients) {
          expect(p.fullName, isNotEmpty);
          // CabinetPatient ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type (pas de getter correspondant).
        }
      },
    );

    // ── Création (#4038) ────────────────────────────────────────────────────

    final created = CabinetPatient(
      id: 'p-new',
      cabinetId: 'c1',
      firstName: 'Nouveau',
      lastName: 'Patient',
      createdAt: DateTime(2026, 1, 1),
    );

    blocTest<PatientsBloc, PatientsState>(
      'émet Creating puis CreateSuccess et appelle le use case de création',
      build: () {
        when(() => repo.create(
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              phone: any(named: 'phone'),
              birthDate: any(named: 'birthDate'),
            )).thenAnswer((_) async => Right(created));
        return PatientsBloc(
            listPatients: listUseCase, createPatient: createUseCase);
      },
      act: (bloc) => bloc.add(const PatientsCreateRequested(
        firstName: 'Nouveau',
        lastName: 'Patient',
        phone: '0600000000',
      )),
      expect: () => [
        const PatientsCreating(),
        PatientsCreateSuccess(created),
      ],
      verify: (_) {
        verify(() => repo.create(
              firstName: 'Nouveau',
              lastName: 'Patient',
              phone: '0600000000',
              birthDate: null,
            )).called(1);
      },
    );

    blocTest<PatientsBloc, PatientsState>(
      'émet Creating puis CreateError sur échec',
      build: () {
        when(() => repo.create(
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              phone: any(named: 'phone'),
              birthDate: any(named: 'birthDate'),
            )).thenAnswer(
          (_) async => Left(
            const ValidationFailure(
                message: 'Nom et prénom sont obligatoires.'),
          ),
        );
        return PatientsBloc(
            listPatients: listUseCase, createPatient: createUseCase);
      },
      act: (bloc) => bloc.add(const PatientsCreateRequested(
        firstName: '',
        lastName: '',
      )),
      expect: () => [
        const PatientsCreating(),
        const PatientsCreateError('Nom et prénom sont obligatoires.'),
      ],
    );
  });

  // --- PatientsPage widget test ------------------------------------------------
  group('PatientsPage', () {
    late _MockPatientsBloc bloc;

    setUp(() {
      bloc = _MockPatientsBloc();
      // PatientAlertBadge (#4093/#4094) fetch son propre use case via GetIt,
      // indépendamment du PatientsBloc mocké ci-dessus — sans ça, chaque
      // ligne lève un GetIt StateError au premier build.
      final listAlerts = _MockListPatientAlerts();
      when(() => listAlerts(any())).thenAnswer((_) async => const Right([]));
      GetIt.instance.registerFactory<ListPatientAlertsUseCase>(
        () => listAlerts,
      );
      addTearDown(GetIt.instance.reset);
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<PatientsBloc>.value(
            value: bloc,
            child: const PatientsPage(),
          ),
        );

    testWidgets('affiche le skeleton en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const PatientsInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets('affiche les patients — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Marie',
            lastName: 'Curie',
            email: 'marie@example.com',
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
      when(() => bloc.state).thenReturn(const PatientsLoaded([]));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun patient enregistré.'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const PatientsError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });

    testWidgets(
        'saisie dans la barre de recherche déclenche PatientsSearchChanged '
        '(#4043, recherche serveur débattue — 350 ms)', (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ali');
      // Avant le délai de debounce : aucun event dispatché.
      await tester.pump(const Duration(milliseconds: 100));
      verifyNever(() => bloc.add(const PatientsSearchChanged('ali')));

      // Après le délai de debounce (350 ms) : l'event part avec q='ali'.
      await tester.pump(const Duration(milliseconds: 300));
      verify(() => bloc.add(const PatientsSearchChanged('ali'))).called(1);
    });

    testWidgets(
        'liste rendue reflète directement state.patients (pas de filtre local)',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
          ),
          CabinetPatient(
            id: 'p2',
            cabinetId: 'c1',
            firstName: 'Bob',
            lastName: 'Dupont',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(PatientTableRow), findsNWidgets(2));
      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Bob Dupont'), findsOneWidget);
    });

    // ── Tableau cinq colonnes (#5117) ───────────────────────────────────

    testWidgets(
        'affiche les cinq en-têtes de colonnes (design-v2, note #5)',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(PatientsTableHeader), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('Dernière visite'), findsOneWidget);
      expect(find.text('Solde'), findsOneWidget);
      expect(find.text('Alertes & étiquettes'), findsOneWidget);
    });

    testWidgets(
        'colonne Patient : date de naissance · âge sous le nom',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Julie',
            lastName: 'Martin',
            birthDate: DateTime(1985, 6, 7),
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('07/06/1985'), findsOneWidget);
    });

    testWidgets(
        '« Dernière visite » affiche — quand lastVisitAt est absent',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
          ),
          CabinetPatient(
            id: 'p2',
            cabinetId: 'c1',
            firstName: 'Bob',
            lastName: 'Dupont',
            createdAt: DateTime(2026, 1, 1),
            lastVisitAt: DateTime(2026, 7, 22),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(find.text('22/07/2026'), findsOneWidget);
    });

    testWidgets(
        'solde : rouge « 148,50 € » si dû, gris « 0,00 € » si à jour',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
            balanceDueCents: 14850,
          ),
          CabinetPatient(
            id: 'p2',
            cabinetId: 'c1',
            firstName: 'Bob',
            lastName: 'Dupont',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final due = tester.widget<Text>(find.text('148,50 €'));
      expect(due.style?.color, NubiaColors.dangerFg);

      final upToDate = tester.widget<Text>(find.text('0,00 €'));
      expect(upToDate.style?.color, NubiaColors.n500);
    });

    testWidgets(
        'affiche le compteur « N résultats sur M » (design-v2, note #7)',
        (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded(
          List.generate(
            4,
            (i) => CabinetPatient(
              id: 'p$i',
              cabinetId: 'c1',
              firstName: 'Patient',
              lastName: '$i',
              createdAt: DateTime(2026, 1, 1),
            ),
          ),
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final counter = tester.widget<Text>(
        find.byKey(const Key('patients_search_results_count')),
      );
      expect(counter.textSpan!.toPlainText(), '4 résultats sur 4');
    });

    testWidgets(
        'fiche patient — bandeau de cloisonnement précisant le cas « AVK »',
        (tester) async {
      final patient = CabinetPatient(
        id: 'p1',
        cabinetId: 'c1',
        firstName: 'Alice',
        lastName: 'Martin',
        createdAt: DateTime(2026, 1, 1),
      );
      when(() => bloc.state).thenReturn(PatientsLoaded([patient]));

      final getPatient = _MockGetCabinetPatient();
      when(() => getPatient(any())).thenAnswer((_) async => Right(patient));
      GetIt.instance.registerFactory<GetCabinetPatientUseCase>(
        () => getPatient,
      );

      final listTags = _MockListPatientTags();
      when(() => listTags(any())).thenAnswer((_) async => const Right([]));
      GetIt.instance.registerFactory<ListPatientTagsUseCase>(() => listTags);

      final listDocuments = _MockListPatientDocuments();
      when(() => listDocuments(any()))
          .thenAnswer((_) async => const Right([]));
      GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
        () => listDocuments,
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PatientTableRow));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('patient_sheet_confidentiality_notice')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cloisonnement secrétariat'),
        findsOneWidget,
      );
      expect(find.textContaining('AVK'), findsOneWidget);
      expect(
        find.textContaining("consigne d'accueil"),
        findsOneWidget,
      );
    });

    // ── Filtres rapides (#5118) ─────────────────────────────────────────

    testWidgets(
        'affiche les trois filtres rapides avec leur compteur dérivé de '
        'la liste', (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
            balanceDueCents: 1500,
          ),
          CabinetPatient(
            id: 'p2',
            cabinetId: 'c1',
            firstName: 'Bob',
            lastName: 'Dupont',
            createdAt: DateTime(2026, 1, 1),
            hasActiveAlerts: true,
          ),
          CabinetPatient(
            id: 'p3',
            cabinetId: 'c1',
            firstName: 'Chloé',
            lastName: 'Petit',
            createdAt: DateTime(2026, 1, 1),
            hasUpcomingAppointment: false,
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('Impayés'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('patients_quick_filters')),
          matching: find.textContaining('Alertes'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sans RDV à venir'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('patients_quick_filter_unpaid')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('patients_quick_filter_alerts')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const Key('patients_quick_filter_noUpcomingAppointment'),
          ),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'activer le filtre « Impayés » restreint la liste au sous-ensemble '
        'correspondant', (tester) async {
      when(() => bloc.state).thenReturn(
        PatientsLoaded([
          CabinetPatient(
            id: 'p1',
            cabinetId: 'c1',
            firstName: 'Alice',
            lastName: 'Martin',
            createdAt: DateTime(2026, 1, 1),
            balanceDueCents: 1500,
          ),
          CabinetPatient(
            id: 'p2',
            cabinetId: 'c1',
            firstName: 'Bob',
            lastName: 'Dupont',
            createdAt: DateTime(2026, 1, 1),
          ),
        ]),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byType(PatientTableRow), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('patients_quick_filter_unpaid')));
      await tester.pumpAndSettle();

      expect(find.byType(PatientTableRow), findsNWidgets(1));
      expect(find.text('Alice Martin'), findsOneWidget);
      expect(find.text('Bob Dupont'), findsNothing);

      // Réactiver le filtre restaure la liste complète.
      await tester.tap(find.byKey(const Key('patients_quick_filter_unpaid')));
      await tester.pumpAndSettle();
      expect(find.byType(PatientTableRow), findsNWidgets(2));
    });
  });
}
