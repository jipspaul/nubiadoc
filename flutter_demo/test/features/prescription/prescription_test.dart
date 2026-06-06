import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/prescription/bloc/prescription_bloc.dart';
import 'package:flutter_demo/features/prescription/bloc/prescription_event.dart';
import 'package:flutter_demo/features/prescription/bloc/prescription_state.dart';
import 'package:flutter_demo/features/prescription/models/prescription.dart';
import 'package:flutter_demo/features/prescription/prescription_screen.dart';
import 'package:flutter_demo/features/prescription/widgets/prescription_form.dart';
import 'package:flutter_demo/features/prescription/widgets/prescription_recap_card.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockPrescriptionBloc
    extends MockBloc<PrescriptionEvent, PrescriptionState>
    implements PrescriptionBloc {}

final _patients = <PatientSummary>[
  const PatientSummary(id: 'pat-001', name: 'Alice Dupont'),
];

final _mockPrescription = Prescription(
  id: 'rx-001',
  patientId: 'pat-001',
  patientName: 'Alice Dupont',
  items: const [
    PrescriptionItem(
      label: 'Amoxicilline',
      posology: '1 cp 3x/j',
      duration: '7 jours',
      quantity: '21',
    ),
  ],
  status: PrescriptionStatus.draft,
);

final _signedPrescription = Prescription(
  id: 'rx-001',
  patientId: 'pat-001',
  patientName: 'Alice Dupont',
  items: _mockPrescription.items,
  status: PrescriptionStatus.signed,
);

Widget _wrap(Widget child, PrescriptionBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<PrescriptionBloc>.value(value: bloc, child: child),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const PrescriptionLoadRequested());
  });

  late MockPrescriptionBloc mockBloc;

  setUp(() {
    mockBloc = MockPrescriptionBloc();
  });

  group('PrescriptionScreen', () {
    testWidgets('renders without throwing on loading state', (tester) async {
      when(() => mockBloc.state).thenReturn(const PrescriptionLoading());
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      expect(find.byType(PrescriptionScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows form when list loaded', (tester) async {
      when(() => mockBloc.state).thenReturn(
        PrescriptionListLoaded(prescriptions: [], patients: _patients),
      );
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      expect(find.byType(PrescriptionForm), findsOneWidget);
    });

    testWidgets('shows recap card when prescription created', (tester) async {
      when(() => mockBloc.state).thenReturn(
        PrescriptionCreated(
          prescription: _mockPrescription,
          patients: _patients,
        ),
      );
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      await tester.pump();
      expect(find.byType(PrescriptionRecapCard), findsOneWidget);
    });

    testWidgets('shows recap card when prescription signed', (tester) async {
      when(() => mockBloc.state).thenReturn(
        PrescriptionSigned(
          prescription: _signedPrescription,
          patients: _patients,
        ),
      );
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      await tester.pump();
      expect(find.byType(PrescriptionRecapCard), findsOneWidget);
    });

    testWidgets('shows error view on PrescriptionError', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const PrescriptionError('Erreur réseau'));
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      expect(find.text('Erreur réseau'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('retry dispatches PrescriptionLoadRequested', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const PrescriptionError('Erreur réseau'));
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      verify(() => mockBloc.add(const PrescriptionLoadRequested())).called(1);
    });
  });

  group('PrescriptionForm', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: PrescriptionForm(
              patients: _patients,
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );
      expect(find.byType(PrescriptionForm), findsOneWidget);
    });

    testWidgets('shows patient dropdown and first item fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: PrescriptionForm(
              patients: _patients,
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('dropdown_patient')), findsOneWidget);
      expect(find.byKey(const Key('field_label_0')), findsOneWidget);
      expect(find.byKey(const Key('btn_create')), findsOneWidget);
    });

    testWidgets('add item button adds a new medication row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: PrescriptionForm(
              patients: _patients,
              onSubmit: (_, __) {},
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('field_label_0')), findsOneWidget);
      expect(find.byKey(const Key('field_label_1')), findsNothing);
      await tester.tap(find.byKey(const Key('btn_add_item')));
      await tester.pump();
      expect(find.byKey(const Key('field_label_1')), findsOneWidget);
    });

    testWidgets('submit dispatches PrescriptionCreateRequested via bloc',
        (tester) async {
      when(() => mockBloc.state).thenReturn(
        PrescriptionListLoaded(prescriptions: [], patients: _patients),
      );
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));

      // Sélectionner le patient.
      await tester.tap(find.byKey(const Key('dropdown_patient')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice Dupont').last);
      await tester.pumpAndSettle();

      // Remplir la ligne médicament.
      await tester.enterText(
          find.byKey(const Key('field_label_0')), 'Amoxicilline');
      await tester.enterText(
          find.byKey(const Key('field_posology_0')), '1 cp 3x/j');
      await tester.enterText(
          find.byKey(const Key('field_duration_0')), '7 jours');
      await tester.enterText(find.byKey(const Key('field_quantity_0')), '21');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_create')));
      await tester.pump();

      final captured = verify(
        () => mockBloc.add(captureAny()),
      ).captured;
      expect(
        captured.any((e) => e is PrescriptionCreateRequested),
        isTrue,
      );
    });
  });

  group('PrescriptionRecapCard', () {
    testWidgets('renders draft with sign button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: PrescriptionRecapCard(
              prescription: _mockPrescription,
              patients: _patients,
              onSign: () {},
              onNew: () {},
            ),
          ),
        ),
      );
      expect(find.byType(PrescriptionRecapCard), findsOneWidget);
      expect(find.byKey(const Key('btn_sign')), findsOneWidget);
      expect(find.text('Amoxicilline'), findsOneWidget);
    });

    testWidgets('renders signed without sign button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: PrescriptionRecapCard(
              prescription: _signedPrescription,
              patients: _patients,
              onSign: null,
              onNew: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('btn_sign')), findsNothing);
      expect(find.byKey(const Key('btn_new_prescription')), findsOneWidget);
    });

    testWidgets('sign button dispatches PrescriptionSignRequested via screen',
        (tester) async {
      when(() => mockBloc.state).thenReturn(
        PrescriptionCreated(
          prescription: _mockPrescription,
          patients: _patients,
        ),
      );
      await tester.pumpWidget(_wrap(const PrescriptionScreen(), mockBloc));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_sign')));
      await tester.pump();

      final captured = verify(
        () => mockBloc.add(captureAny()),
      ).captured;
      expect(
        captured.any((e) =>
            e is PrescriptionSignRequested && e.id == _mockPrescription.id),
        isTrue,
      );
    });
  });
}
