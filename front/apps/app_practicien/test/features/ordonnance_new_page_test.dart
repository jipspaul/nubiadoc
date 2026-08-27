import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/ordonnances/ordonnance_new_page.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_bloc.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_event.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_state.dart';
import 'package:app_practicien/features/ordonnances/send_to_pharmacy_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks & fixtures
// ---------------------------------------------------------------------------

class MockOrdonnancesBloc extends MockBloc<OrdonnancesEvent, OrdonnancesState>
    implements OrdonnancesBloc {}

class _StubDirectoryRepository extends Mock
    implements PharmacyDirectoryRepository {}

class _StubPrescriptionRepository extends Mock
    implements PrescriptionRepository {}

class _MockMedicalRecordRepository extends Mock
    implements MedicalRecordRepository {}

final _medicalRecordRepo = _MockMedicalRecordRepository();

/// `_PrescriptionFormState` résout `GetMedicalRecordUseCase` via GetIt
/// (#4076, même pattern que `SendToPharmacyCubit` ci-dessus) — un mock
/// partagé, re-stubbable par test (`when` écrase la stub précédente).
void registerMedicalRecordStub() {
  when(() => _medicalRecordRepo.getMedicalRecord(any())).thenAnswer(
    (_) async =>
        const Right(MedicalRecordSummary(allergies: [], treatments: [])),
  );
  if (GetIt.instance.isRegistered<GetMedicalRecordUseCase>()) return;
  GetIt.instance.registerFactory<GetMedicalRecordUseCase>(
    () => GetMedicalRecordUseCase(_medicalRecordRepo),
  );
}

/// La confirmation de signature monte SendToPharmacyCubit via GetIt (F9) :
/// on enregistre un cubit réel branché sur des stubs sans pharmacie déclarée.
void registerSendToPharmacyStub() {
  final directory = _StubDirectoryRepository();
  when(() => directory.getPatientPharmacy(any()))
      .thenAnswer((_) async => const Right(null));
  if (GetIt.instance.isRegistered<SendToPharmacyCubit>()) return;
  GetIt.instance.registerFactory<SendToPharmacyCubit>(
    () => SendToPharmacyCubit(
      getPatientPharmacy: GetPatientPharmacyUseCase(directory),
      sendToPharmacy:
          SendPrescriptionToPharmacyUseCase(_StubPrescriptionRepository()),
    ),
  );
}

const _item = PrescriptionItem(
  label: 'Amoxicilline 500mg',
  posology: '1 comprimé matin et soir',
  duration: '7 jours',
  quantity: '1 boîte',
);

final _prescription = Prescription(
  id: 'presc-1',
  patientId: 'patient-1',
  items: const [_item],
  status: PrescriptionStatus.draft,
  createdAt: DateTime(2026, 7, 2),
);

const _templateItem = PrescriptionItem(
  label: 'Paracétamol 1 g',
  form: 'comprimé',
  posology: '1 cp x 3/jour si douleur',
  duration: '5 jours',
  quantity: 'QSP 15 cp',
);

const _template = PrescriptionTemplate(
  id: 'tmpl-1',
  label: 'Antalgique post-opératoire palier 1',
  items: [_templateItem],
  isGlobal: true,
);

/// Devis (ordonnance) tel que renvoyé après application du modèle #4074 :
/// mêmes lignes que le modèle, `id`/`patientId` inchangés.
final _prescriptionWithTemplateItems = Prescription(
  id: 'presc-1',
  patientId: 'patient-1',
  items: const [_templateItem],
  status: PrescriptionStatus.draft,
  createdAt: DateTime(2026, 7, 2),
);

Widget _wrap(OrdonnancesBloc bloc, {String? patientId = 'patient-1'}) =>
    MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<OrdonnancesBloc>.value(
          value: bloc,
          child: OrdonnanceNewBody(patientId: patientId),
        ),
      ),
    );

Future<void> _fillItem(WidgetTester tester, int index) async {
  await tester.enterText(
      find.byKey(Key('item_${index}_label')), 'Amoxicilline 500mg');
  await tester.pump();
  await tester.enterText(
      find.byKey(Key('item_${index}_posology')), '1 comprimé matin et soir');
  await tester.pump();
  await tester.enterText(find.byKey(Key('item_${index}_duration')), '7 jours');
  await tester.pump();
  await tester.enterText(find.byKey(Key('item_${index}_quantity')), '1 boîte');
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(registerSendToPharmacyStub);

  late MockOrdonnancesBloc bloc;

  setUp(() {
    bloc = MockOrdonnancesBloc();
    when(() => bloc.state).thenReturn(const OrdonnancesInitial());
    registerMedicalRecordStub();
  });

  group('OrdonnanceNewBody', () {
    testWidgets('sans patientId → empty state de guidage', (tester) async {
      await tester.pumpWidget(_wrap(bloc, patientId: null));

      expect(find.byKey(const Key('ordonnances_new')), findsOneWidget);
      expect(find.byKey(const Key('ordonnance_form')), findsNothing);
    });

    testWidgets('avec patientId → formulaire affiché, submit désactivé à vide',
        (tester) async {
      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('ordonnance_form')), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('submit_ordonnance_button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('patient avec allergie renseignée → bandeau affiché (#4076)',
        (tester) async {
      when(() => _medicalRecordRepo.getMedicalRecord('patient-1')).thenAnswer(
        (_) async => const Right(
          MedicalRecordSummary(allergies: ['Pénicilline'], treatments: []),
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('allergies_banner')), findsOneWidget);
      expect(find.text('Allergies connues au dossier'), findsOneWidget);
      expect(find.text('Pénicilline'), findsOneWidget);
      expect(
        find.textContaining('Affichage informatif'),
        findsOneWidget,
      );
      expect(
        find.textContaining('hors périmètre dispositif médical (ADR-009 §8.6)'),
        findsOneWidget,
      );
    });

    testWidgets('patient sans allergie → aucun bandeau affiché (#4076)',
        (tester) async {
      when(() => _medicalRecordRepo.getMedicalRecord('patient-1')).thenAnswer(
        (_) async =>
            const Right(MedicalRecordSummary(allergies: [], treatments: [])),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('allergies_banner')), findsNothing);
    });

    testWidgets(
        'patient avec allergie → aucun champ de saisie désactivé (#4076)',
        (tester) async {
      when(() => _medicalRecordRepo.getMedicalRecord('patient-1')).thenAnswer(
        (_) async => const Right(
          MedicalRecordSummary(allergies: ['Pénicilline'], treatments: []),
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('allergies_banner')), findsOneWidget);
      // La saisie reste pleinement utilisable : les champs sont éditables et
      // le bouton "Ajouter un médicament" reste actif.
      final addButton =
          tester.widget<NubiaButton>(find.byKey(const Key('add_item_button')));
      expect(addButton.onPressed, isNotNull);
      await _fillItem(tester, 0);
      final submitButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('submit_ordonnance_button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(submitButton.onPressed, isNotNull);
    });

    testWidgets(
        'formulaire complet → submit dispatch OrdonnancesCreateRequested',
        (tester) async {
      await tester.pumpWidget(_wrap(bloc));
      await _fillItem(tester, 0);

      await tester
          .ensureVisible(find.byKey(const Key('submit_ordonnance_button')));
      await tester.tap(find.byKey(const Key('submit_ordonnance_button')));

      verify(
        () => bloc.add(
          const OrdonnancesCreateRequested(
            patientId: 'patient-1',
            items: [_item],
          ),
        ),
      ).called(1);
    });

    testWidgets('bouton Ajouter → deuxième carte médicament', (tester) async {
      await tester.pumpWidget(_wrap(bloc));

      await tester.ensureVisible(find.byKey(const Key('add_item_button')));
      await tester.tap(find.byKey(const Key('add_item_button')));
      await tester.pump();

      expect(find.byKey(const Key('item_card_0')), findsOneWidget);
      expect(find.byKey(const Key('item_card_1')), findsOneWidget);
    });

    testWidgets('OrdonnancesCreated → relecture brouillon + bouton Signer',
        (tester) async {
      when(() => bloc.state).thenReturn(OrdonnancesCreated(_prescription));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('ordonnance_draft_review')), findsOneWidget);
      expect(find.text('Amoxicilline 500mg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sign_ordonnance_button')));
      verify(() => bloc.add(const OrdonnancesSignRequested('presc-1')))
          .called(1);
    });

    testWidgets(
        'OrdonnancesCreated → mention eIDAS d\'immutabilité visible sous les CTA (#5001)',
        (tester) async {
      when(() => bloc.state).thenReturn(OrdonnancesCreated(_prescription));

      await tester.pumpWidget(_wrap(bloc));

      expect(
        find.textContaining('Signature électronique'),
        findsOneWidget,
      );
      expect(
        find.textContaining('document horodaté et non modifiable'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sign_ordonnance_button')), findsOneWidget);
    });

    testWidgets(
        'OrdonnancesCreated → sélectionner un modèle préremplit les lignes affichées (#4075)',
        (tester) async {
      // État initial : un brouillon existant (une ligne).
      when(() => bloc.state).thenReturn(OrdonnancesCreated(_prescription));
      when(() => bloc.loadTemplates())
          .thenAnswer((_) async => const [_template]);

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('use_template_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('use_template_button')));
      await tester.pumpAndSettle();

      // Le picker affiche le modèle (catalogue global).
      expect(find.byKey(const Key('prescription_template_picker')),
          findsOneWidget);
      expect(find.byKey(const Key('prescription_template_tmpl-1')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('prescription_template_tmpl-1')));
      await tester.pumpAndSettle();

      verify(() => bloc.add(const OrdonnancesApplyTemplateRequested(
            prescriptionId: 'presc-1',
            templateId: 'tmpl-1',
          ))).called(1);
    });

    testWidgets(
        'OrdonnancesCreated avec les lignes du modèle appliqué → label/posologie/durée affichés',
        (tester) async {
      // Simule l'état APRÈS application réussie du modèle (bloc mis à jour) :
      // les lignes affichées doivent être celles du modèle, pas du brouillon initial.
      when(() => bloc.state)
          .thenReturn(OrdonnancesCreated(_prescriptionWithTemplateItems));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Paracétamol 1 g'), findsOneWidget);
      expect(find.text('1 cp x 3/jour si douleur — 5 jours'), findsOneWidget);
    });

    testWidgets(
        'OrdonnancesApplyingTemplate → relecture brouillon, bouton modèle en chargement',
        (tester) async {
      when(() => bloc.state)
          .thenReturn(OrdonnancesApplyingTemplate(_prescription));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('ordonnance_draft_review')), findsOneWidget);
      final signButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('sign_ordonnance_button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(signButton.onPressed, isNull,
          reason:
              'Signer doit être désactivé pendant l\'application du modèle');
    });

    testWidgets('OrdonnancesSigned → confirmation', (tester) async {
      when(() => bloc.state).thenReturn(OrdonnancesSigned(
        Prescription(
          id: 'presc-1',
          patientId: 'patient-1',
          items: const [_item],
          status: PrescriptionStatus.signed,
          createdAt: DateTime(2026, 7, 2),
        ),
      ));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('ordonnance_signed_confirmation')),
          findsOneWidget);
      expect(find.text('Ordonnance signée'), findsOneWidget);
    });

    testWidgets('OrdonnancesError → snackbar, formulaire toujours monté',
        (tester) async {
      whenListen(
        bloc,
        Stream.fromIterable([const OrdonnancesError('Erreur de création.')]),
        initialState: const OrdonnancesInitial(),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.text('Erreur de création.'), findsOneWidget);
      expect(find.byKey(const Key('ordonnance_form')), findsOneWidget);
    });
  });
}
