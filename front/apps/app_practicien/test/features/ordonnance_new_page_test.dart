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
