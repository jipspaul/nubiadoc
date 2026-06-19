import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/pro_config.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetSessionUseCase extends Mock implements GetSessionUseCase {}

class MockAddActUseCase extends Mock implements AddActUseCase {}

class MockCompleteSessionUseCase extends Mock
    implements CompleteSessionUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _session = ClinicalSession(
  id: 'session-1',
  appointmentId: 'apt-1',
  status: 'in_progress',
  acts: const [],
);

final _act = const ClinicalAct(
  id: 'act-1',
  ccamCode: 'HBMD035',
  label: 'Extraction dentaire',
  amountCents: 2300,
);

ConsultationCliniqueBloc _makeBloc({
  required MockGetSessionUseCase getSession,
  required MockAddActUseCase addAct,
  required MockCompleteSessionUseCase completeSession,
}) =>
    ConsultationCliniqueBloc(
      getSession: getSession,
      addAct: addAct,
      completeSession: completeSession,
    );

Widget _wrap(ConsultationCliniqueBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _Body()),
      ),
    );

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      builder: (context, state) {
        if (state is ConsultationCliniqueInitial ||
            state is ConsultationCliniqueLoading) {
          return const Center(
            key: Key('consultation_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ConsultationCliniqueError) {
          return Center(
            key: const Key('consultation_error'),
            child: Text(state.message),
          );
        }
        if (state is ConsultationCliniqueLoaded) {
          final acts = state.session.acts;
          return Column(
            children: [
              Expanded(
                child: acts.isEmpty
                    ? const Center(
                        key: Key('consultation_no_acts'),
                        child: Text('Aucun acte CCAM enregistré'),
                      )
                    : ListView(
                        children: [
                          for (final a in acts)
                            Text(key: Key('act_${a.id}'), a.label),
                        ],
                      ),
              ),
              ElevatedButton(
                key: const Key('complete_button'),
                onPressed: state.actionInProgress
                    ? null
                    : () => context
                        .read<ConsultationCliniqueBloc>()
                        .add(const ConsultationCliniqueCompleted()),
                child: const Text('Terminer'),
              ),
            ],
          );
        }
        if (state is ConsultationCliniqueCompleteSuccess) {
          return const Center(
            key: Key('consultation_complete'),
            child: Text('Consultation terminée'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests — flux nominal
// ---------------------------------------------------------------------------

void main() {
  late MockGetSessionUseCase mockGetSession;
  late MockAddActUseCase mockAddAct;
  late MockCompleteSessionUseCase mockCompleteSession;

  setUp(() {
    mockGetSession = MockGetSessionUseCase();
    mockAddAct = MockAddActUseCase();
    mockCompleteSession = MockCompleteSessionUseCase();
  });

  group('ConsultationCliniqueBloc', () {
    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'émet Loading puis Loaded avec la session',
      build: () {
        when(() => mockGetSession('session-1'))
            .thenAnswer((_) async => Right(_session));
        return _makeBloc(
          getSession: mockGetSession,
          addAct: mockAddAct,
          completeSession: mockCompleteSession,
        );
      },
      act: (bloc) =>
          bloc.add(const ConsultationCliniqueLoadRequested('session-1')),
      expect: () => [
        const ConsultationCliniqueLoading(),
        ConsultationCliniqueLoaded(session: _session),
      ],
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'émet Error quand le chargement échoue',
      build: () {
        when(() => mockGetSession('session-1')).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(
          getSession: mockGetSession,
          addAct: mockAddAct,
          completeSession: mockCompleteSession,
        );
      },
      act: (bloc) =>
          bloc.add(const ConsultationCliniqueLoadRequested('session-1')),
      expect: () => [
        const ConsultationCliniqueLoading(),
        const ConsultationCliniqueError('Réseau indisponible'),
      ],
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'ActAdded ajoute l\'acte CCAM à la liste',
      build: () {
        when(() => mockGetSession('session-1'))
            .thenAnswer((_) async => Right(_session));
        when(
          () => mockAddAct(
            consultationId: 'session-1',
            ccamCode: 'HBMD035',
            label: 'Extraction dentaire',
            tooth: null,
            amountCents: null,
          ),
        ).thenAnswer((_) async => Right(_act));
        return _makeBloc(
          getSession: mockGetSession,
          addAct: mockAddAct,
          completeSession: mockCompleteSession,
        );
      },
      act: (bloc) async {
        bloc.add(const ConsultationCliniqueLoadRequested('session-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ConsultationCliniqueActAdded(
          ccamCode: 'HBMD035',
          label: 'Extraction dentaire',
        ));
      },
      expect: () => [
        const ConsultationCliniqueLoading(),
        ConsultationCliniqueLoaded(session: _session),
        ConsultationCliniqueLoaded(session: _session, actionInProgress: true),
        ConsultationCliniqueLoaded(
          session: ClinicalSession(
            id: 'session-1',
            appointmentId: 'apt-1',
            status: 'in_progress',
            acts: [_act],
          ),
        ),
      ],
    );

    blocTest<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      'Completed émet CompleteSuccess',
      build: () {
        when(() => mockGetSession('session-1'))
            .thenAnswer((_) async => Right(_session));
        when(() => mockCompleteSession('session-1')).thenAnswer(
          (_) async => const Right(SessionCompleteResult(invoiceId: 'inv-1')),
        );
        return _makeBloc(
          getSession: mockGetSession,
          addAct: mockAddAct,
          completeSession: mockCompleteSession,
        );
      },
      act: (bloc) async {
        bloc.add(const ConsultationCliniqueLoadRequested('session-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ConsultationCliniqueCompleted());
      },
      expect: () => [
        const ConsultationCliniqueLoading(),
        ConsultationCliniqueLoaded(session: _session),
        const ConsultationCliniqueCompleteSuccess(invoiceId: 'inv-1'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests — flux nominal
  // ---------------------------------------------------------------------------

  group('ConsultationCliniquePage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockGetSession('session-1'))
          .thenAnswer((_) async => Right(_session));
      final bloc = _makeBloc(
        getSession: mockGetSession,
        addAct: mockAddAct,
        completeSession: mockCompleteSession,
      );
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('consultation_loading')), findsOneWidget);
    });

    testWidgets('affiche "aucun acte" après chargement (liste vide)',
        (tester) async {
      when(() => mockGetSession('session-1'))
          .thenAnswer((_) async => Right(_session));
      final bloc = _makeBloc(
        getSession: mockGetSession,
        addAct: mockAddAct,
        completeSession: mockCompleteSession,
      )..add(const ConsultationCliniqueLoadRequested('session-1'));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('consultation_no_acts')), findsOneWidget);
      expect(find.byKey(const Key('complete_button')), findsOneWidget);
    });

    testWidgets('affiche les actes CCAM après chargement', (tester) async {
      final sessionWithActs = ClinicalSession(
        id: 'session-1',
        appointmentId: 'apt-1',
        status: 'in_progress',
        acts: [_act],
      );
      when(() => mockGetSession('session-1'))
          .thenAnswer((_) async => Right(sessionWithActs));
      final bloc = _makeBloc(
        getSession: mockGetSession,
        addAct: mockAddAct,
        completeSession: mockCompleteSession,
      )..add(const ConsultationCliniqueLoadRequested('session-1'));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('act_act-1')), findsOneWidget);
      expect(find.byKey(const Key('complete_button')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockGetSession('session-1')).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = _makeBloc(
        getSession: mockGetSession,
        addAct: mockAddAct,
        completeSession: mockCompleteSession,
      )..add(const ConsultationCliniqueLoadRequested('session-1'));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('consultation_error')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Gating guard — destination cachée quand canAccessClinical=false
  // ---------------------------------------------------------------------------

  group('ProConfig — gating clinique praticien', () {
    test('includeClinical est true pour app_practicien', () {
      expect(ProConfig.includeClinical, isTrue);
    });

    test('la destination Consultation a requiresClinical: true', () {
      final consultationDest = ProConfig.shellConfig.destinations
          .where((d) => d.route == '/consultation')
          .toList();
      expect(consultationDest, hasLength(1));
      expect(consultationDest.first.requiresClinical, isTrue);
    });
  });

  group('ProShell — destination Consultation cachée quand canAccessClinical=false',
      () {
    const secretarySession = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.secretary,
    );

    const practitionerSession = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.practitioner,
    );

    Widget buildShell(AuthSession session) => MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfig,
            session: session,
          ),
        );

    testWidgets(
      'destination Consultation absente du widget tree quand secrétaire (canAccessClinical=false)',
      (tester) async {
        await tester.pumpWidget(buildShell(secretarySession));
        await tester.pumpAndSettle();
        expect(find.text('Consultation'), findsNothing);
      },
    );

    testWidgets(
      'destination Consultation visible quand praticien (canAccessClinical=true)',
      (tester) async {
        await tester.pumpWidget(buildShell(practitionerSession));
        await tester.pumpAndSettle();
        expect(find.text('Consultation'), findsWidgets);
      },
    );
  });
}
