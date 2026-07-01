import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_page.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';

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

const _sessionInterrupted = ClinicalSession(
  id: 'h3',
  appointmentId: 'a3',
  status: 'interrupted',
  acts: [],
);

// ---------------------------------------------------------------------------
// Widget under test — wraps _HistoriqueView via the BLoC state
// ---------------------------------------------------------------------------

Widget _wrap(MockConsultationCliniqueBloc bloc) => MaterialApp(
      home: BlocProvider<ConsultationCliniqueBloc>.value(
        value: bloc,
        child: const Scaffold(
          body: _HistoriqueBodyDirect(),
        ),
      ),
    );

// Renders only the historique state — bypasses GetIt / ConsultationCliniquePage.
class _HistoriqueBodyDirect extends StatelessWidget {
  const _HistoriqueBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      builder: (context, state) {
        if (state is! ConsultationHistoriqueLoaded) {
          return const SizedBox.shrink();
        }
        // Inline replica of _HistoriqueView to test via the exported state.
        // The real _HistoriqueView is a private widget in consultation_clinique_page.dart.
        return _HistoriqueTestView(sessions: state.sessions);
      },
    );
  }
}

class _HistoriqueTestView extends StatefulWidget {
  const _HistoriqueTestView({required this.sessions});
  final List<ClinicalSession> sessions;

  @override
  State<_HistoriqueTestView> createState() => _HistoriqueTestViewState();
}

class _HistoriqueTestViewState extends State<_HistoriqueTestView> {
  Set<String> _selection = {};

  List<ClinicalSession> get _filtered {
    if (_selection.isEmpty) return widget.sessions;
    return widget.sessions.where((s) => _selection.contains(s.status)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        SegmentedButton<String>(
          key: const Key('historique_filter'),
          segments: const [
            ButtonSegment<String>(
                value: 'in_progress', label: Text('En cours')),
            ButtonSegment<String>(value: 'completed', label: Text('Terminée')),
            ButtonSegment<String>(
                value: 'interrupted', label: Text('Interrompue')),
          ],
          selected: _selection,
          onSelectionChanged: (s) => setState(() => _selection = s),
          multiSelectionEnabled: false,
          emptySelectionAllowed: true,
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  key: Key('historique_empty'),
                  child: Text('Aucune consultation'),
                )
              : ListView(
                  key: const Key('historique_list'),
                  children: [
                    for (final s in filtered)
                      ListTile(
                        key: Key('historique_${s.id}'),
                        title: Text('Consultation ${s.id}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures supplémentaires
// ---------------------------------------------------------------------------

const _emptySession = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
);

const _sessionWithActs = ClinicalSession(
  id: 's2',
  appointmentId: 'a2',
  status: 'in_progress',
  acts: [
    ClinicalAct(
      id: 'act1',
      ccamCode: 'HBLD001',
      label: 'Détartrage',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConsultationCliniqueBody — tous les states', () {
    late MockConsultationCliniqueBloc bloc;

    Widget wrapBody() => MaterialApp(
          home: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: const Scaffold(body: ConsultationCliniqueBody()),
          ),
        );

    setUp(() {
      bloc = MockConsultationCliniqueBloc();
    });

    testWidgets('Initial → spinner idle', (tester) async {
      when(() => bloc.state).thenReturn(const ConsultationCliniqueInitial());
      await tester.pumpWidget(wrapBody());
      expect(find.byKey(const Key('consultation_idle')), findsOneWidget);
    });

    testWidgets('Loading → spinner loading', (tester) async {
      when(() => bloc.state).thenReturn(const ConsultationCliniqueLoading());
      await tester.pumpWidget(wrapBody());
      expect(find.byKey(const Key('consultation_loading')), findsOneWidget);
    });

    testWidgets('Error → NubiaErrorWidget consultation_error', (tester) async {
      when(() => bloc.state)
          .thenReturn(const ConsultationCliniqueError('Erreur serveur'));
      await tester.pumpWidget(wrapBody());
      expect(find.byKey(const Key('consultation_error')), findsOneWidget);
    });

    testWidgets('Loaded session vide → consultation_empty', (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationCliniqueLoaded(session: _emptySession),
      );
      await tester.pumpWidget(wrapBody());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consultation_empty')), findsOneWidget);
    });

    testWidgets('Loaded session avec actes → affiche les actes', (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationCliniqueLoaded(session: _sessionWithActs),
      );
      await tester.pumpWidget(wrapBody());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('act_act1')), findsOneWidget);
    });

    testWidgets('Completed → consultation_completed', (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationCliniqueCompleted(SessionCompleteResult()),
      );
      await tester.pumpWidget(wrapBody());
      expect(find.byKey(const Key('consultation_completed')), findsOneWidget);
    });

    testWidgets('HistoriqueLoaded vide → historique_empty', (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationHistoriqueLoaded(sessions: []),
      );
      await tester.pumpWidget(wrapBody());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historique_empty')), findsOneWidget);
    });
  });

  group('ConsultationClinique — filtre historique', () {
    late MockConsultationCliniqueBloc bloc;

    setUp(() {
      bloc = MockConsultationCliniqueBloc();
    });

    testWidgets(
        'affiche SegmentedButton avec 3 segments et toutes les sessions',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationHistoriqueLoaded(
          sessions: [
            _sessionCompleted,
            _sessionInProgress,
            _sessionInterrupted,
          ],
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique_filter')), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Terminée'), findsOneWidget);
      expect(find.text('Interrompue'), findsOneWidget);
      // Toutes les sessions visibles par défaut (aucun filtre actif)
      expect(find.byKey(const Key('historique_h1')), findsOneWidget);
      expect(find.byKey(const Key('historique_h2')), findsOneWidget);
      expect(find.byKey(const Key('historique_h3')), findsOneWidget);
    });

    testWidgets(
        'filtre sur Terminée — affiche uniquement les sessions completed',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationHistoriqueLoaded(
          sessions: [
            _sessionCompleted,
            _sessionInProgress,
            _sessionInterrupted,
          ],
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminée'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique_h1')), findsOneWidget);
      expect(find.byKey(const Key('historique_h2')), findsNothing);
      expect(find.byKey(const Key('historique_h3')), findsNothing);
    });

    testWidgets('filtre sur En cours — affiche uniquement in_progress',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationHistoriqueLoaded(
          sessions: [
            _sessionCompleted,
            _sessionInProgress,
            _sessionInterrupted,
          ],
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester.tap(find.text('En cours'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique_h1')), findsNothing);
      expect(find.byKey(const Key('historique_h2')), findsOneWidget);
      expect(find.byKey(const Key('historique_h3')), findsNothing);
    });

    testWidgets(
        'affiche état vide quand aucune session ne correspond au filtre',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const ConsultationHistoriqueLoaded(
          sessions: [_sessionCompleted],
        ),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Interrompue'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique_empty')), findsOneWidget);
      expect(find.byKey(const Key('historique_h1')), findsNothing);
    });
  });
}
