import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/clinical_session/bloc/clinical_session_bloc.dart';
import 'package:flutter_demo/features/clinical_session/bloc/clinical_session_event.dart';
import 'package:flutter_demo/features/clinical_session/bloc/clinical_session_state.dart';
import 'package:flutter_demo/features/clinical_session/clinical_session_screen.dart';
import 'package:flutter_demo/features/clinical_session/models/ccam_act.dart';
import 'package:flutter_demo/features/clinical_session/models/clinical_session.dart';
import 'package:flutter_demo/features/clinical_session/widgets/ccam_act_form.dart';
import 'package:flutter_demo/features/clinical_session/widgets/ccam_act_list.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockClinicalSessionBloc
    extends MockBloc<ClinicalSessionEvent, ClinicalSessionState>
    implements ClinicalSessionBloc {}

const _mockSession = ClinicalSession(
  id: 'cs-apt-001',
  appointmentId: 'apt-001',
  patientName: 'Patient Démo',
  status: SessionStatus.inProgress,
  acts: [],
);

const _mockAct = CcamAct(
  id: 'act-1',
  ccamCode: 'HBQD001',
  label: 'Extraction dentaire',
  tooth: '11',
  amountCents: 9000,
);

Widget _wrap(Widget child, ClinicalSessionBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<ClinicalSessionBloc>.value(value: bloc, child: child),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const SessionStartRequested(appointmentId: 'apt-001'),
    );
  });

  late MockClinicalSessionBloc mockBloc;

  setUp(() {
    mockBloc = MockClinicalSessionBloc();
  });

  group('ClinicalSessionScreen — état initial', () {
    testWidgets('affiche le bouton Démarrer sur état Initial', (tester) async {
      when(() => mockBloc.state).thenReturn(const ClinicalSessionInitial());
      await tester.pumpWidget(
        _wrap(
          const ClinicalSessionScreen(appointmentId: 'apt-001'),
          mockBloc,
        ),
      );
      expect(find.byKey(const Key('btn_start_session')), findsOneWidget);
    });

    testWidgets('tap Démarrer dispatche SessionStartRequested', (tester) async {
      when(() => mockBloc.state).thenReturn(const ClinicalSessionInitial());
      await tester.pumpWidget(
        _wrap(
          const ClinicalSessionScreen(appointmentId: 'apt-001'),
          mockBloc,
        ),
      );
      await tester.tap(find.byKey(const Key('btn_start_session')));
      await tester.pump();
      verify(
        () => mockBloc.add(
          const SessionStartRequested(appointmentId: 'apt-001'),
        ),
      ).called(1);
    });
  });

  group('ClinicalSessionScreen — état Loading', () {
    testWidgets('affiche CircularProgressIndicator', (tester) async {
      when(() => mockBloc.state).thenReturn(const ClinicalSessionLoading());
      await tester.pumpWidget(
        _wrap(
          const ClinicalSessionScreen(appointmentId: 'apt-001'),
          mockBloc,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ClinicalSessionScreen — état Active', () {
    testWidgets('affiche le nom du patient et le bouton Terminer',
        (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const ClinicalSessionActive(_mockSession));
      await tester.pumpWidget(
        _wrap(
          const ClinicalSessionScreen(appointmentId: 'apt-001'),
          mockBloc,
        ),
      );
      expect(find.text('Patient Démo'), findsOneWidget);
      expect(find.byKey(const Key('btn_complete_session')), findsOneWidget);
    });

    testWidgets('tap Terminer dispatche SessionCompleteRequested',
        (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const ClinicalSessionActive(_mockSession));
      await tester.pumpWidget(
        _wrap(
          const ClinicalSessionScreen(appointmentId: 'apt-001'),
          mockBloc,
        ),
      );
      await tester.tap(find.byKey(const Key('btn_complete_session')));
      await tester.pump();
      verify(
        () => mockBloc.add(
          const SessionCompleteRequested(consultationId: 'cs-apt-001'),
        ),
      ).called(1);
    });

    testWidgets('affiche le formulaire CCAM', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const ClinicalSessionActive(_mockSession));
      await tester.pumpWidget(
        _wrap(
          const ClinicalSessionScreen(appointmentId: 'apt-001'),
          mockBloc,
        ),
      );
      expect(find.byType(CcamActForm), findsOneWidget);
    });
  });

  group('CcamActForm', () {
    testWidgets('rendu sans erreur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: CcamActForm(
              onSubmit: ({required ccamCode, required label, tooth, amountCents}) {},
            ),
          ),
        ),
      );
      expect(find.byType(CcamActForm), findsOneWidget);
    });

    testWidgets('soumettre un acte valide appelle onSubmit', (tester) async {
      String? capturedCode;
      String? capturedLabel;
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: CcamActForm(
              onSubmit: ({
                required ccamCode,
                required label,
                tooth,
                amountCents,
              }) {
                capturedCode = ccamCode;
                capturedLabel = label;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('field_ccam_code')), 'HBQD001');
      await tester.enterText(
          find.byKey(const Key('field_ccam_label')), 'Extraction');
      await tester.tap(find.byKey(const Key('btn_add_act')));
      await tester.pump();
      expect(capturedCode, 'HBQD001');
      expect(capturedLabel, 'Extraction');
    });

    testWidgets('ne soumet pas si code vide', (tester) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: CcamActForm(
              onSubmit: ({required ccamCode, required label, tooth, amountCents}) {
                called = true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('btn_add_act')));
      await tester.pump();
      expect(called, isFalse);
    });
  });

  group('CcamActList', () {
    testWidgets('affiche message vide quand liste vide', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: CcamActList(acts: const [], onRemove: (_) {}),
          ),
        ),
      );
      expect(find.text('Aucun acte ajouté'), findsOneWidget);
    });

    testWidgets('affiche les actes et le bouton retirer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: CcamActList(acts: const [_mockAct], onRemove: (_) {}),
          ),
        ),
      );
      expect(find.text('Extraction dentaire'), findsOneWidget);
      expect(find.text('HBQD001 · Dent 11'), findsOneWidget);
      expect(find.byKey(Key('btn_remove_act_${_mockAct.id}')), findsOneWidget);
    });

    testWidgets('tap retirer appelle onRemove avec le bon id', (tester) async {
      String? removedId;
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: CcamActList(
              acts: const [_mockAct],
              onRemove: (id) => removedId = id,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(Key('btn_remove_act_${_mockAct.id}')));
      await tester.pump();
      expect(removedId, _mockAct.id);
    });
  });
}
