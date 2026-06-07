import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_bloc.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_event.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_state.dart';
import 'package:nubia_patient/presentation/features/prescription/pages/prescription_screen.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockPrescriptionBloc
    extends MockBloc<PrescriptionEvent, PrescriptionState>
    implements PrescriptionBloc {}

PrescriptionItem _makeItem() => const PrescriptionItem(
      label: 'Amoxicilline',
      form: 'gélules',
      posology: '1 gélule matin et soir',
      duration: '7 jours',
      quantity: '14',
    );

Prescription _makePrescription({PrescriptionStatus status = PrescriptionStatus.draft}) =>
    Prescription(
      id: 'presc-1',
      patientId: 'patient-1',
      items: [_makeItem()],
      status: status,
      createdAt: DateTime(2026, 6, 7),
    );

Widget _wrap(PrescriptionBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<PrescriptionBloc>.value(
      value: bloc,
      child: const PrescriptionScreen(),
    ),
  );
}

void main() {
  late MockPrescriptionBloc bloc;

  setUp(() => bloc = MockPrescriptionBloc());
  tearDown(() => bloc.close());

  // -------------------------------------------------------------------------
  // Initial state
  // -------------------------------------------------------------------------

  testWidgets(
    'PrescriptionScreen affiche le formulaire médicament en état Initial',
    (tester) async {
      when(() => bloc.state).thenReturn(const PrescriptionInitial());

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Ajouter un médicament'), findsOneWidget);
    },
  );

  testWidgets(
    "PrescriptionScreen affiche le bouton Créer l'ordonnance en état Initial",
    (tester) async {
      when(() => bloc.state).thenReturn(const PrescriptionInitial());

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text("Créer l'ordonnance"), findsOneWidget);
    },
  );

  testWidgets(
    'Bouton Créer est désactivé sans patient ni médicament',
    (tester) async {
      when(() => bloc.state).thenReturn(const PrescriptionInitial());

      await tester.pumpWidget(_wrap(bloc));

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('create_prescription_button')),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'Bouton Créer est actif avec patient et médicaments',
    (tester) async {
      when(() => bloc.state).thenReturn(
        PrescriptionInitial(
          patientId: 'patient-1',
          patientName: 'Jean Dupont',
          items: [_makeItem()],
        ),
      );

      await tester.pumpWidget(_wrap(bloc));

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('create_prescription_button')),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'Tap Créer envoie PrescriptionCreateRequested',
    (tester) async {
      when(() => bloc.state).thenReturn(
        PrescriptionInitial(
          patientId: 'patient-1',
          patientName: 'Jean Dupont',
          items: [_makeItem()],
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.tap(find.byKey(const Key('create_prescription_button')));
      await tester.pump();

      verify(() => bloc.add(const PrescriptionCreateRequested())).called(1);
    },
  );

  // -------------------------------------------------------------------------
  // Loading state
  // -------------------------------------------------------------------------

  testWidgets(
    'PrescriptionScreen affiche un loader en état Loading',
    (tester) async {
      when(() => bloc.state).thenReturn(const PrescriptionLoading());

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------------
  // Loaded — draft
  // -------------------------------------------------------------------------

  testWidgets(
    'PrescriptionScreen affiche le récap et le bouton Signer pour un draft',
    (tester) async {
      when(() => bloc.state)
          .thenReturn(PrescriptionLoaded(_makePrescription()));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Statut : Brouillon'), findsOneWidget);
      expect(find.text('Signer'), findsOneWidget);
      expect(find.text('Amoxicilline — gélules'), findsOneWidget);
    },
  );

  testWidgets(
    'Tap Signer envoie PrescriptionSignRequested',
    (tester) async {
      when(() => bloc.state)
          .thenReturn(PrescriptionLoaded(_makePrescription()));

      await tester.pumpWidget(_wrap(bloc));
      await tester.tap(find.byKey(const Key('sign_prescription_button')));
      await tester.pump();

      verify(() => bloc.add(const PrescriptionSignRequested())).called(1);
    },
  );

  // -------------------------------------------------------------------------
  // Loaded — signed
  // -------------------------------------------------------------------------

  testWidgets(
    'PrescriptionScreen affiche Signée et cache le bouton Signer',
    (tester) async {
      when(() => bloc.state).thenReturn(
        PrescriptionLoaded(
          _makePrescription(status: PrescriptionStatus.signed),
        ),
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Statut : Signée'), findsOneWidget);
      expect(find.byKey(const Key('sign_prescription_button')), findsNothing);
    },
  );

  // -------------------------------------------------------------------------
  // Error state
  // -------------------------------------------------------------------------

  testWidgets(
    'PrescriptionScreen affiche le message d\'erreur',
    (tester) async {
      when(() => bloc.state)
          .thenReturn(const PrescriptionError('Erreur réseau'));

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Erreur réseau'), findsOneWidget);
    },
  );
}
