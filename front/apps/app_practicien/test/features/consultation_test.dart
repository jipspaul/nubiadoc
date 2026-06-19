import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation/consultation_bloc.dart';
import 'package:app_practicien/features/consultation/consultation_event.dart';
import 'package:app_practicien/features/consultation/consultation_state.dart';

class MockGetSessionUseCase extends Mock implements GetSessionUseCase {}
class MockAddActUseCase extends Mock implements AddActUseCase {}
class MockRemoveActUseCase extends Mock implements RemoveActUseCase {}
class MockCompleteSessionUseCase extends Mock implements CompleteSessionUseCase {}

const _cid = 'consult-1';
final _act = ClinicalAct(id: 'act-1', ccamCode: 'HBFD001', label: 'Détartrage');
final _session = ClinicalSession(
    id: _cid, appointmentId: 'appt-1', status: 'in_progress', acts: [_act]);
final _empty = ClinicalSession(
    id: _cid, appointmentId: 'appt-1', status: 'in_progress', acts: const []);

ConsultationBloc _bloc(
  MockGetSessionUseCase g,
  MockAddActUseCase a,
  MockRemoveActUseCase r,
  MockCompleteSessionUseCase c,
) =>
    ConsultationBloc(getSession: g, addAct: a, removeAct: r, completeSession: c);

Widget _wrap(ConsultationBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(
          body: BlocBuilder<ConsultationBloc, ConsultationState>(
            builder: (ctx, s) {
              if (s is ConsultationInitial || s is ConsultationLoading) {
                return const Center(key: Key('loading'), child: CircularProgressIndicator());
              }
              if (s is ConsultationError) return Center(key: const Key('error'), child: Text(s.message));
              if (s is ConsultationCompleted) return const Center(key: Key('done'), child: Text('Done'));
              if (s is ConsultationLoaded) {
                return s.session.acts.isEmpty
                    ? const Center(key: Key('empty'), child: Text('Vide'))
                    : Column(children: [for (final a in s.session.acts) Text(key: Key('act_${a.id}'), a.label)]);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

void main() {
  late MockGetSessionUseCase g;
  late MockAddActUseCase a;
  late MockRemoveActUseCase r;
  late MockCompleteSessionUseCase c;

  setUp(() {
    g = MockGetSessionUseCase();
    a = MockAddActUseCase();
    r = MockRemoveActUseCase();
    c = MockCompleteSessionUseCase();
  });

  group('ConsultationBloc', () {
    blocTest<ConsultationBloc, ConsultationState>(
      'load → Loaded',
      build: () {
        when(() => g(_cid)).thenAnswer((_) async => Right(_session));
        return _bloc(g, a, r, c);
      },
      act: (b) => b.add(const ConsultationLoadRequested(_cid)),
      expect: () => [const ConsultationLoading(), ConsultationLoaded(session: _session)],
    );

    blocTest<ConsultationBloc, ConsultationState>(
      'load → Error',
      build: () {
        when(() => g(_cid)).thenAnswer((_) async => Left(NetworkFailure('Réseau')));
        return _bloc(g, a, r, c);
      },
      act: (b) => b.add(const ConsultationLoadRequested(_cid)),
      expect: () => [const ConsultationLoading(), const ConsultationError('Réseau')],
    );

    blocTest<ConsultationBloc, ConsultationState>(
      'ActAdd → recharge après succès',
      build: () {
        when(() => a(
              consultationId: any(named: 'consultationId'),
              ccamCode: any(named: 'ccamCode'),
              label: any(named: 'label'),
              tooth: any(named: 'tooth'),
              amountCents: any(named: 'amountCents'),
              included: any(named: 'included'),
            )).thenAnswer((_) async => Right(_act));
        when(() => g(_cid)).thenAnswer((_) async => Right(_session));
        return _bloc(g, a, r, c);
      },
      seed: () => ConsultationLoaded(session: _empty),
      act: (b) => b.add(const ConsultationActAddRequested(
          consultationId: _cid, ccamCode: 'HBFD001', label: 'Détartrage')),
      expect: () => [
        ConsultationLoaded(session: _empty, actionInProgress: true),
        const ConsultationLoading(),
        ConsultationLoaded(session: _session),
      ],
    );

    blocTest<ConsultationBloc, ConsultationState>(
      'ActAdd → erreur préservée',
      build: () {
        when(() => a(
              consultationId: any(named: 'consultationId'),
              ccamCode: any(named: 'ccamCode'),
              label: any(named: 'label'),
              tooth: any(named: 'tooth'),
              amountCents: any(named: 'amountCents'),
              included: any(named: 'included'),
            )).thenAnswer((_) async => Left(NetworkFailure('Err')));
        return _bloc(g, a, r, c);
      },
      seed: () => ConsultationLoaded(session: _empty),
      act: (b) => b.add(const ConsultationActAddRequested(
          consultationId: _cid, ccamCode: 'HBFD001', label: 'Détartrage')),
      expect: () => [
        ConsultationLoaded(session: _empty, actionInProgress: true),
        ConsultationLoaded(session: _empty, actionError: 'Err'),
      ],
    );

    blocTest<ConsultationBloc, ConsultationState>(
      'Complete → ConsultationCompleted',
      build: () {
        when(() => c(_cid))
            .thenAnswer((_) async => const Right(SessionCompleteResult()));
        return _bloc(g, a, r, c);
      },
      seed: () => ConsultationLoaded(session: _session),
      act: (b) => b.add(const ConsultationCompleteRequested(_cid)),
      expect: () => [
        ConsultationLoaded(session: _session, actionInProgress: true),
        const ConsultationCompleted(SessionCompleteResult()),
      ],
    );

    blocTest<ConsultationBloc, ConsultationState>(
      'Complete → erreur préservée',
      build: () {
        when(() => c(_cid)).thenAnswer((_) async => Left(NetworkFailure('Err')));
        return _bloc(g, a, r, c);
      },
      seed: () => ConsultationLoaded(session: _session),
      act: (b) => b.add(const ConsultationCompleteRequested(_cid)),
      expect: () => [
        ConsultationLoaded(session: _session, actionInProgress: true),
        ConsultationLoaded(session: _session, actionError: 'Err'),
      ],
    );
  });

  group('ConsultationPage (widget)', () {
    testWidgets('chargement initial', (t) async {
      when(() => g(_cid)).thenAnswer((_) async => Right(_session));
      await t.pumpWidget(_wrap(_bloc(g, a, r, c)));
      expect(find.byKey(const Key('loading')), findsOneWidget);
    });

    testWidgets('affiche les actes', (t) async {
      when(() => g(_cid)).thenAnswer((_) async => Right(_session));
      final b = _bloc(g, a, r, c)..add(const ConsultationLoadRequested(_cid));
      await t.pumpWidget(_wrap(b));
      await t.pump();
      expect(find.byKey(const Key('act_act-1')), findsOneWidget);
    });

    testWidgets('affiche la vue terminée', (t) async {
      when(() => c(_cid)).thenAnswer((_) async => const Right(SessionCompleteResult()));
      final b = _bloc(g, a, r, c);
      await t.pumpWidget(_wrap(b));
      b.emit(ConsultationLoaded(session: _session));
      await t.pump();
      b.add(const ConsultationCompleteRequested(_cid));
      await t.pump();
      expect(find.byKey(const Key('done')), findsOneWidget);
    });
  });
}
