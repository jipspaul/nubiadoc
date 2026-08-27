import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/ordonnances/ordonnance_new_page.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_bloc.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_event.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_state.dart';
import 'package:app_practicien/features/ordonnances/send_to_pharmacy_cubit.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

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

class _MockCabinetPatientsRepository extends Mock
    implements CabinetPatientsRepository {}

final _cabinetPatientsRepo = _MockCabinetPatientsRepository();

final _patient = CabinetPatient(
  id: 'patient-1',
  cabinetId: 'cab-1',
  firstName: 'Julie',
  lastName: 'Martin',
  birthDate: DateTime(1985, 6, 7),
  createdAt: DateTime(2024, 1, 1),
);

/// En-tête d'identité patient (#4999) : `_PrescriptionFormState` résout
/// `GetCabinetPatientUseCase` via GetIt, même pattern que
/// `registerMedicalRecordStub` ci-dessus.
void registerCabinetPatientStub() {
  when(() => _cabinetPatientsRepo.getById(any()))
      .thenAnswer((_) async => Right(_patient));
  if (GetIt.instance.isRegistered<GetCabinetPatientUseCase>()) return;
  GetIt.instance.registerFactory<GetCabinetPatientUseCase>(
    () => GetCabinetPatientUseCase(_cabinetPatientsRepo),
  );
}

class MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

/// Praticien connecté (#4999, en-tête d'identité patient) — `displayName`
/// fixe pour le segment « suivi(e) par Dr … » du sous-titre.
MockProAuthCubit _makeAuthCubit() {
  final cubit = MockProAuthCubit();
  when(() => cubit.state).thenReturn(
    const AuthAuthenticated(
      AuthSession(
        kind: UserKind.pro,
        userId: 'me',
        role: ProRole.practitioner,
        displayName: 'A. Rousseau',
      ),
    ),
  );
  return cubit;
}

final _pharmacyDirectoryRepo = _StubDirectoryRepository();
final _prescriptionRepo = _StubPrescriptionRepository();

const _pharmacy = Pharmacy(
  id: 'pharma-1',
  name: 'Pharmacie du Port',
  address: '3 rue Haute, Paris',
);

/// La confirmation de signature (et l'action combinée #5000) montent
/// SendToPharmacyCubit via GetIt (F9) : on enregistre un cubit réel branché
/// sur des stubs re-stubbables par test (par défaut, sans pharmacie
/// déclarée).
void registerSendToPharmacyStub() {
  when(() => _pharmacyDirectoryRepo.getPatientPharmacy(any()))
      .thenAnswer((_) async => const Right(null));
  when(() => _prescriptionRepo.sendToPharmacy(
        prescriptionId: any(named: 'prescriptionId'),
        pharmacyId: any(named: 'pharmacyId'),
      )).thenAnswer((_) async => Right(_prescription));
  if (GetIt.instance.isRegistered<SendToPharmacyCubit>()) return;
  GetIt.instance.registerFactory<SendToPharmacyCubit>(
    () => SendToPharmacyCubit(
      getPatientPharmacy: GetPatientPharmacyUseCase(_pharmacyDirectoryRepo),
      sendToPharmacy: SendPrescriptionToPharmacyUseCase(_prescriptionRepo),
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
        body: MultiBlocProvider(
          providers: [
            BlocProvider<OrdonnancesBloc>.value(value: bloc),
            BlocProvider<ProAuthCubit>.value(value: _makeAuthCubit()),
          ],
          child: OrdonnanceNewBody(patientId: patientId),
        ),
      ),
    );

/// Sélectionne [label] dans la feuille ouverte par le `NubiaSelect` de clé
/// [key] (#4991 : dose/fréquence/durée en listes déroulantes, plus en
/// texte libre).
Future<void> _select(WidgetTester tester, Key key, String label) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Remplit une ligne médicament avec une dose/fréquence/durée dont la
/// quantité se calcule automatiquement (#4992) : 1 comprimé × 2 fois / jour
/// × 7 jours = 14 comprimés — aucune saisie de quantité n'est plus
/// nécessaire.
Future<void> _fillItem(WidgetTester tester, int index) async {
  await tester.enterText(
      find.byKey(Key('item_${index}_label')), 'Amoxicilline 500mg');
  await tester.pump();
  await _select(tester, Key('item_${index}_posology'), '1 comprimé');
  await _select(tester, Key('item_${index}_frequency'), '2 fois / jour');
  await _select(tester, Key('item_${index}_duration'), '7 jours');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockOrdonnancesBloc bloc;

  setUp(() {
    bloc = MockOrdonnancesBloc();
    when(() => bloc.state).thenReturn(const OrdonnancesInitial());
    registerMedicalRecordStub();
    registerCabinetPatientStub();
    registerSendToPharmacyStub();
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

    testWidgets(
        'avec patientId → en-tête d\'identité patient (nom, âge, DDN, '
        'prescripteur, Brouillon) (#4999)', (tester) async {
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ordonnance_patient_header')), findsOneWidget);
      expect(find.text('Julie Martin'), findsOneWidget);
      expect(find.text('Brouillon'), findsOneWidget);
      expect(
        find.text('41 ans · né(e) le 07/06/1985 · suivi(e) par Dr A. Rousseau'),
        findsOneWidget,
      );
      expect(find.text('Médicaments à prescrire'), findsNothing);
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
        'formulaire complet → submit dispatch OrdonnancesCreateRequested '
        'avec la quantité calculée (#4992)', (tester) async {
      await tester.pumpWidget(_wrap(bloc));
      await _fillItem(tester, 0);

      await tester
          .ensureVisible(find.byKey(const Key('submit_ordonnance_button')));
      await tester.tap(find.byKey(const Key('submit_ordonnance_button')));

      // _fillItem : 1 comprimé × 2 fois / jour × 7 jours = 14 comprimés.
      verify(
        () => bloc.add(
          const OrdonnancesCreateRequested(
            patientId: 'patient-1',
            items: [
              PrescriptionItem(
                label: 'Amoxicilline 500mg',
                posology: '1 comprimé, 2 fois / jour',
                duration: '7 jours',
                quantity: '14 comprimés',
              ),
            ],
          ),
        ),
      ).called(1);
    });

    group('quantité calculée (#4992)', () {
      testWidgets('aucun champ de saisie libre par défaut', (tester) async {
        await tester.pumpWidget(_wrap(bloc));

        expect(find.byKey(const Key('item_0_quantity')), findsNothing);
        expect(
            find.byKey(const Key('item_0_quantity_calc')), findsOneWidget);
        expect(find.byKey(const Key('item_0_quantity_modify')),
            findsOneWidget);
      });

      testWidgets(
          'dose × fréquence × durée → recalculée à chaque changement',
          (tester) async {
        await tester.pumpWidget(_wrap(bloc));

        expect(find.textContaining('Quantité calculée :'), findsOneWidget);
        expect(find.textContaining('renseignez la posologie'), findsOneWidget);

        await _select(tester, const Key('item_0_posology'), '1 comprimé');
        await _select(tester, const Key('item_0_frequency'), '3 fois / jour');
        await _select(tester, const Key('item_0_duration'), '5 jours');

        // 1 × 3 × 5 = 15 comprimés.
        expect(find.textContaining('Quantité calculée : 15 comprimés'),
            findsOneWidget);

        await _select(tester, const Key('item_0_duration'), '10 jours');

        expect(find.textContaining('Quantité calculée : 30 comprimés'),
            findsOneWidget);
      });

      testWidgets('« Modifier » permet de surcharger la quantité calculée',
          (tester) async {
        await tester.pumpWidget(_wrap(bloc));
        await tester.enterText(
            find.byKey(const Key('item_0_label')), 'Amoxicilline 500mg');
        await tester.pump();
        await _select(tester, const Key('item_0_posology'), '1 comprimé');
        await _select(tester, const Key('item_0_frequency'), '3 fois / jour');
        await _select(tester, const Key('item_0_duration'), '5 jours');

        await tester.tap(find.byKey(const Key('item_0_quantity_modify')));
        await tester.pump();

        expect(find.byKey(const Key('item_0_quantity_calc')), findsNothing);
        final field = find.byKey(const Key('item_0_quantity'));
        expect(field, findsOneWidget);
        // Le champ de surcharge démarre pré-rempli avec la valeur calculée.
        expect(
          tester
              .widget<NubiaTextField>(field)
              .controller
              ?.text,
          '15 comprimés',
        );

        await tester.enterText(field, '1 boîte de 16');
        await tester.pump();

        await tester
            .ensureVisible(find.byKey(const Key('submit_ordonnance_button')));
        await tester.tap(find.byKey(const Key('submit_ordonnance_button')));

        verify(
          () => bloc.add(
            OrdonnancesCreateRequested(
              patientId: 'patient-1',
              items: [
                PrescriptionItem(
                  label: 'Amoxicilline 500mg',
                  posology: '1 comprimé, 3 fois / jour',
                  duration: '5 jours',
                  quantity: '1 boîte de 16',
                ),
              ],
            ),
          ),
        ).called(1);
      });

      testWidgets(
          'sans dose/fréquence/durée sélectionnées → ligne invalide (submit désactivé)',
          (tester) async {
        await tester.pumpWidget(_wrap(bloc));
        await tester.enterText(
            find.byKey(const Key('item_0_label')), 'Vaccin');
        await tester.pump();
        await _select(tester, const Key('item_0_posology'), '1 comprimé');
        await _select(tester, const Key('item_0_frequency'), '2 fois / jour');
        // Durée non sélectionnée : ligne incomplète.

        final submitButton = tester.widget<FilledButton>(
          find.descendant(
            of: find.byKey(const Key('submit_ordonnance_button')),
            matching: find.byType(FilledButton),
          ),
        );
        expect(submitButton.onPressed, isNull);
      });
    });

    testWidgets(
        'tablette large (1258×834) → composition et aperçu côte à côte, '
        'volet aperçu ~458 px (#4998)', (tester) async {
      tester.view.physicalSize = const Size(1258, 834);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ordonnance_form')), findsOneWidget);
      expect(
          find.byKey(const Key('ordonnance_document_preview')), findsOneWidget);

      final previewWidth = tester
          .getSize(find.byKey(const Key('ordonnance_document_preview')))
          .width;
      expect(previewWidth, closeTo(458, 1));

      final formLeft =
          tester.getTopLeft(find.byKey(const Key('ordonnance_form'))).dx;
      final previewLeft = tester
          .getTopLeft(find.byKey(const Key('ordonnance_document_preview')))
          .dx;
      expect(previewLeft, greaterThan(formLeft));
    });

    testWidgets('écran étroit → pas de volet aperçu, formulaire pleine largeur',
        (tester) async {
      tester.view.physicalSize = const Size(700, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ordonnance_form')), findsOneWidget);
      expect(
          find.byKey(const Key('ordonnance_document_preview')), findsNothing);
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
        'OrdonnancesCreated → bouton combiné "Signer et envoyer à la pharmacie" présent, dispatch la signature au tap (#5000)',
        (tester) async {
      when(() => bloc.state).thenReturn(OrdonnancesCreated(_prescription));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('sign_ordonnance_button')), findsOneWidget);
      expect(find.byKey(const Key('sign_and_send_to_pharmacy_button')),
          findsOneWidget);

      await tester
          .tap(find.byKey(const Key('sign_and_send_to_pharmacy_button')));
      verify(() => bloc.add(const OrdonnancesSignRequested('presc-1')))
          .called(1);
    });

    testWidgets(
        'bouton combiné → signature puis envoi automatique sur la pharmacie déclarée, sans étape manuelle (#5000)',
        (tester) async {
      when(() => _pharmacyDirectoryRepo.getPatientPharmacy('patient-1'))
          .thenAnswer((_) async => const Right(_pharmacy));

      final signed = Prescription(
        id: 'presc-1',
        patientId: 'patient-1',
        items: const [_item],
        status: PrescriptionStatus.signed,
        createdAt: DateTime(2026, 7, 2),
      );

      final controller = StreamController<OrdonnancesState>();
      addTearDown(controller.close);
      whenListen(
        bloc,
        controller.stream,
        initialState: OrdonnancesCreated(_prescription),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester
          .tap(find.byKey(const Key('sign_and_send_to_pharmacy_button')));
      verify(() => bloc.add(const OrdonnancesSignRequested('presc-1')))
          .called(1);

      controller.add(OrdonnancesSigned(signed));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('send_to_pharmacy_done')), findsOneWidget);
      expect(find.textContaining('transmise à Pharmacie du Port'),
          findsOneWidget);
      verify(() => _prescriptionRepo.sendToPharmacy(
            prescriptionId: 'presc-1',
            pharmacyId: 'pharma-1',
          )).called(1);
    });

    testWidgets(
        'bouton combiné → sans pharmacie déclarée, retombe sur le choix de pharmacie sans crash (#5000)',
        (tester) async {
      // Stub par défaut (registerSendToPharmacyStub) : pas de pharmacie
      // déclarée pour le patient.
      final signed = Prescription(
        id: 'presc-1',
        patientId: 'patient-1',
        items: const [_item],
        status: PrescriptionStatus.signed,
        createdAt: DateTime(2026, 7, 2),
      );

      final controller = StreamController<OrdonnancesState>();
      addTearDown(controller.close);
      whenListen(
        bloc,
        controller.stream,
        initialState: OrdonnancesCreated(_prescription),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester
          .tap(find.byKey(const Key('sign_and_send_to_pharmacy_button')));

      controller.add(OrdonnancesSigned(signed));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('send_to_pharmacy_card')), findsOneWidget);
      expect(find.byKey(const Key('choose_pharmacy_button')), findsOneWidget);
      expect(find.byKey(const Key('send_to_pharmacy_done')), findsNothing);
      verifyNever(() => _prescriptionRepo.sendToPharmacy(
            prescriptionId: any(named: 'prescriptionId'),
            pharmacyId: any(named: 'pharmacyId'),
          ));
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
