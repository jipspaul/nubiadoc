import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/features/consultation_clinique/widgets/consultation_historique_view.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _sessionCompleted = ClinicalSession(
  id: 'h1',
  appointmentId: 'a1',
  status: 'completed',
  acts: [],
);

const _sessionInProgress = ClinicalSession(
  id: 'h2',
  appointmentId: 'a2',
  status: 'in_progress',
  acts: [],
);

// ---------------------------------------------------------------------------
// Widget under test — le vrai `HistoriqueView` (#7033 : le filtre doit
// redemander la liste au serveur, jamais trier la page déjà chargée).
// ---------------------------------------------------------------------------

Widget _wrap(
  MockConsultationCliniqueBloc bloc, {
  required List<ClinicalSession> sessions,
  String? selectedStatus,
}) =>
    MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<ConsultationCliniqueBloc>.value(
        value: bloc,
        child: Scaffold(
          body: HistoriqueView(
            sessions: sessions,
            selectedStatus: selectedStatus,
          ),
        ),
      ),
    );

// Les Keys des segments ne sont pas exposées : on scope la recherche de
// texte au `SegmentedButton` pour éviter toute collision avec le même
// libellé porté par le `StatusPill` d'une carte (#7033 — sessions).
Finder _segment(String label) => find.descendant(
      of: find.byKey(const Key('historique_filter')),
      matching: find.text(label),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HistoriqueView — filtre historique (#7033)', () {
    late MockConsultationCliniqueBloc bloc;

    setUp(() {
      bloc = MockConsultationCliniqueBloc();
      when(() => bloc.state).thenReturn(const ConsultationHistoriqueLoaded(
        sessions: [],
      ));
    });

    testWidgets(
        'affiche SegmentedButton avec 3 segments et les sessions fournies '
        'par le bloc', (tester) async {
      await tester.pumpWidget(_wrap(bloc, sessions: const [
        _sessionCompleted,
        _sessionInProgress,
      ]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique_filter')), findsOneWidget);
      expect(_segment('En cours'), findsOneWidget);
      expect(_segment('Terminée'), findsOneWidget);
      expect(_segment('Annulée'), findsOneWidget);
      expect(find.byKey(const Key('historique_h1')), findsOneWidget);
      expect(find.byKey(const Key('historique_h2')), findsOneWidget);
    });

    testWidgets(
        'clic sur « En cours » redemande la liste au serveur avec ce '
        'statut, ne trie pas la page déjà chargée', (tester) async {
      // La page déjà chargée ne contient que des séances `completed` — le
      // scénario exact de la QA #7033 : les `in_progress` existent côté
      // serveur mais pas dans la page en mémoire.
      await tester.pumpWidget(_wrap(bloc, sessions: const [
        _sessionCompleted,
      ]));
      await tester.pumpAndSettle();

      await tester.tap(_segment('En cours'));
      await tester.pumpAndSettle();

      verify(() => bloc.add(
            const ConsultationHistoriqueRequested(status: 'in_progress'),
          )).called(1);
    });

    testWidgets(
        'désélection du segment redemande la liste sans filtre (status: '
        'null)', (tester) async {
      await tester.pumpWidget(_wrap(
        bloc,
        sessions: const [_sessionInProgress],
        selectedStatus: 'in_progress',
      ));
      await tester.pumpAndSettle();

      await tester.tap(_segment('En cours'));
      await tester.pumpAndSettle();

      verify(() => bloc.add(
            const ConsultationHistoriqueRequested(),
          )).called(1);
    });

    testWidgets('affiche état vide quand le serveur ne renvoie aucune séance',
        (tester) async {
      await tester.pumpWidget(_wrap(bloc, sessions: const []));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique_empty')), findsOneWidget);
    });
  });
}
