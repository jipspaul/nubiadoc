import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/dashboard_bloc.dart';
import 'package:app_secretariat/features/dashboard/dashboard_event.dart';
import 'package:app_secretariat/features/dashboard/dashboard_state.dart';

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

// Capturés dans `build()` et relus dans `expect()` de leur blocTest
// respectif, pour dériver `practitionersToday` avec la même formule que le
// bloc plutôt que de figer un booléen sensible à l'heure d'exécution.
late DateTime _now1;
late AgendaEntry _a1;
late DateTime _now2;
late AgendaEntry _reqToday;
late AgendaEntry _confToday;
late AgendaEntry _past1;
late AgendaEntry _past2;

Widget _wrap(DashboardBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<DashboardBloc>.value(
        value: bloc,
        child: Scaffold(
          body: BlocBuilder<DashboardBloc, DashboardState>(
            builder: (context, state) {
              if (state is DashboardLoaded) {
                return Column(
                  key: const Key('dashboard_loaded'),
                  children: [
                    Text('RDV: ${state.todayCount}',
                        key: const Key('stat_rdv_today')),
                    Text('En attente: ${state.pendingCount}',
                        key: const Key('stat_pending')),
                    Text('Liste attente: ${state.waitingCount}',
                        key: const Key('stat_waiting_list')),
                  ],
                );
              }
              if (state is DashboardError) {
                return Text(
                  state.message,
                  key: const Key('dashboard_error'),
                );
              }
              // DashboardInitial, DashboardLoading
              return const CircularProgressIndicator(
                key: Key('dashboard_loading'),
              );
            },
          ),
        ),
      ),
    );

class _MockGetAgenda extends Mock implements GetCabinetAgendaUseCase {}

class _MockListWaitingList extends Mock implements ListWaitingListUseCase {}

/// Ancre un DateTime à midi le jour de `base` + `daysOffset` — évite toute
/// dépendance à l'heure d'exécution du test. `now.add(Duration(hours: N))`
/// traverse minuit si le test tourne dans les N heures précédant minuit,
/// faisant "sauter" une entrée censée être aujourd'hui au jour suivant —
/// flake CI observé sur front-test (#3855 : todayCount attendu 2, obtenu 1).
DateTime _atNoon(DateTime base, {int daysOffset = 0}) =>
    DateTime(base.year, base.month, base.day + daysOffset, 12);

AgendaEntry _entry(
  String id,
  DateTime startsAt, {
  bool isFree = false,
  String status = 'requested',
  String practitionerId = 'prac',
  String practitionerName = 'Dr T',
  Duration duration = const Duration(minutes: 30),
}) =>
    AgendaEntry(
      id: id,
      cabinetId: 'cab',
      practitionerId: practitionerId,
      practitionerName: practitionerName,
      startsAt: startsAt,
      endsAt: startsAt.add(duration),
      isFree: isFree,
      status: isFree ? '' : status,
    );

/// Reproduit la formule de `DashboardBloc` pour dériver la présence d'un
/// praticien depuis l'agenda — évite de figer un booléen en dur dans les
/// attentes de test, ce qui serait sensible à l'instant d'exécution du test
/// (cf. `_atNoon` ci-dessus pour le même souci côté date).
bool _isInConsultation(DateTime now, Iterable<AgendaEntry> entries) =>
    entries.any((e) => !now.isBefore(e.startsAt) && now.isBefore(e.endsAt));

void main() {
  group('DashboardBloc', () {
    late _MockGetAgenda getAgenda;
    late _MockListWaitingList listWaitingList;

    setUpAll(() {
      registerFallbackValue(DateTime(2026, 1, 1));
    });

    setUp(() {
      getAgenda = _MockGetAgenda();
      listWaitingList = _MockListWaitingList();
    });

    blocTest<DashboardBloc, DashboardState>(
      '#3362 : compteurs réels — RDV du jour, à confirmer, liste d\'attente',
      build: () {
        final now = DateTime.now();
        _now1 = now;
        _a1 = _entry('a1', _atNoon(now));
        when(() => getAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => Right([
                  _a1,
                  _entry('a2', _atNoon(now, daysOffset: 1)),
                  _entry('libre', _atNoon(now), isFree: true),
                ]));
        when(() => listWaitingList()).thenAnswer(
          (_) async => Right([
            WaitingListEntry(
              id: 'w1',
              cabinetId: 'cab',
              patientId: 'p1',
              patientName: 'Marc Dubois',
              motif: '',
              requestedAt: DateTime(2026, 6, 21),
              position: 1,
            ),
          ]),
        );
        return DashboardBloc(
          getAgenda: getAgenda,
          listWaitingList: listWaitingList,
        );
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        // pendingCount = a1 seulement (#4599 : borné au jour, comme
        // todayCount — a2 est demain, exclu).
        DashboardLoaded(
          todayCount: 1,
          pendingCount: 1,
          waitingCount: 1,
          practitionersToday: [
            PractitionerToday(
              practitionerId: 'prac',
              practitionerName: 'Dr T',
              appointmentCount: 1,
              isInConsultation: _isInConsultation(_now1, [_a1]),
              lastAppointmentEndsAt: _a1.endsAt,
            ),
          ],
        ),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      '#3855 : pendingCount ne compte que status=requested, todayCount exclut cancelled',
      build: () {
        final now = DateTime.now();
        _now2 = now;
        _reqToday = _entry('req-today', _atNoon(now), status: 'requested');
        _confToday = _entry('conf-today', _atNoon(now), status: 'confirmed');
        when(() => getAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => Right([
                  // Aujourd'hui : 1 requested (compte), 1 confirmed (ne
                  // compte pas comme pending, mais compte dans todayCount),
                  // 1 cancelled (ne compte NULLE PART).
                  _reqToday,
                  _confToday,
                  _entry('cancel-today', _atNoon(now), status: 'cancelled'),
                  // Un autre jour : done/no_show/requested, ne comptent pas
                  // dans todayCount ; seul le requested compte en pending.
                  _entry('done-later', _atNoon(now, daysOffset: 2),
                      status: 'done'),
                  _entry('noshow-later', _atNoon(now, daysOffset: 2),
                      status: 'no_show'),
                  _entry('req-later', _atNoon(now, daysOffset: 2),
                      status: 'requested'),
                  _entry('libre', _atNoon(now), isFree: true),
                ]));
        when(() => listWaitingList()).thenAnswer((_) async => const Right([]));
        return DashboardBloc(
          getAgenda: getAgenda,
          listWaitingList: listWaitingList,
        );
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        // todayCount = req-today + conf-today (2) — cancel-today exclu.
        // pendingCount = req-today seulement (1) — confirmed/done/no_show/
        // cancelled tous exclus (avant #3855 : 5, tout non-libre), et
        // req-later exclu car pas aujourd'hui (#4599 : même borne
        // temporelle que todayCount).
        DashboardLoaded(
          todayCount: 2,
          pendingCount: 1,
          waitingCount: 0,
          // req-today + conf-today sont du même praticien ('prac') : une
          // seule entrée agrégée, 2 RDV.
          practitionersToday: [
            PractitionerToday(
              practitionerId: 'prac',
              practitionerName: 'Dr T',
              appointmentCount: 2,
              isInConsultation:
                  _isInConsultation(_now2, [_reqToday, _confToday]),
              lastAppointmentEndsAt: _confToday.endsAt,
            ),
          ],
        ),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      "#5385 : praticiens aujourd'hui — groupés par praticien, en "
      'consultation détecté depuis un RDV en cours',
      build: () {
        final now = DateTime.now();
        // Dr Rousseau : un RDV en cours (brackets `now`) → « en
        // consultation » quel que soit l'instant d'exécution du test.
        final ongoing = _entry(
          'ongoing',
          now.subtract(const Duration(minutes: 10)),
          practitionerId: 'pA',
          practitionerName: 'Dr Amélie Rousseau',
          status: 'in_progress',
          duration: const Duration(minutes: 30),
        );
        final laterToday = _entry(
          'later-today',
          // Ancré sur `_atNoon` (+ 3h, encore largement dans la même
          // journée) plutôt que relatif à `now`, pour ne jamais risquer de
          // franchir minuit selon l'heure d'exécution du test.
          _atNoon(now).add(const Duration(hours: 3)),
          practitionerId: 'pA',
          practitionerName: 'Dr Amélie Rousseau',
          status: 'confirmed',
        );
        // Dr Lefèvre : deux RDV du jour, aucun ne couvre `now`.
        _past1 = _entry(
          'past1',
          _atNoon(now),
          practitionerId: 'pB',
          practitionerName: 'Dr Marc Lefèvre',
          status: 'done',
        );
        _past2 = _entry(
          'past2',
          _atNoon(now).add(const Duration(hours: 1)),
          practitionerId: 'pB',
          practitionerName: 'Dr Marc Lefèvre',
          status: 'done',
        );
        when(() => getAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer(
          (_) async => Right([ongoing, laterToday, _past1, _past2]),
        );
        when(() => listWaitingList()).thenAnswer((_) async => const Right([]));
        return DashboardBloc(
          getAgenda: getAgenda,
          listWaitingList: listWaitingList,
        );
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [const DashboardLoading(), isA<DashboardLoaded>()],
      verify: (bloc) {
        final state = bloc.state as DashboardLoaded;
        final byId = {
          for (final p in state.practitionersToday) p.practitionerId: p,
        };
        expect(byId['pA']!.appointmentCount, 2);
        // `ongoing` brackète `now` par construction (démarré il y a 10 min,
        // se termine dans 20 min) → toujours vrai, quel que soit l'instant
        // d'exécution du test.
        expect(byId['pA']!.isInConsultation, isTrue);
        expect(byId['pB']!.appointmentCount, 2);
        // `past1`/`past2` sont ancrés à midi (comme `_atNoon`, pour éviter
        // tout risque de franchissement de minuit) : on rejoue la même
        // formule que le bloc plutôt que de figer `isFalse`, qui ne serait
        // sûr que si le test tourne hors du créneau 12h-13h30.
        expect(
          byId['pB']!.isInConsultation,
          _isInConsultation(DateTime.now(), [_past1, _past2]),
        );
        expect(
          byId['pB']!.lastAppointmentEndsAt,
          _atNoon(DateTime.now())
              .add(const Duration(hours: 1, minutes: 30)),
        );
      },
    );

    blocTest<DashboardBloc, DashboardState>(
      'agenda en échec → DashboardError (pas un faux 0)',
      build: () {
        when(() => getAgenda(any(), includePast: any(named: 'includePast')))
            .thenAnswer((_) async => const Left(NetworkFailure()));
        when(() => listWaitingList()).thenAnswer((_) async => const Right([]));
        return DashboardBloc(
          getAgenda: getAgenda,
          listWaitingList: listWaitingList,
        );
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [const DashboardLoading(), isA<DashboardError>()],
    );
  });

  group('Dashboard stats cards', () {
    late _MockDashboardBloc bloc;

    setUp(() {
      bloc = _MockDashboardBloc();
    });

    testWidgets('affiche le chargement en état DashboardInitial',
        (tester) async {
      when(() => bloc.state).thenReturn(const DashboardInitial());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche le chargement en état DashboardLoading',
        (tester) async {
      when(() => bloc.state).thenReturn(const DashboardLoading());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche une erreur en état DashboardError', (tester) async {
      when(() => bloc.state)
          .thenReturn(const DashboardError(message: 'Erreur test'));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('dashboard_error')), findsOneWidget);
    });

    testWidgets('émet state avec counts → assert valeurs visibles',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const DashboardLoaded(todayCount: 4, pendingCount: 2, waitingCount: 7),
      );
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard_loaded')), findsOneWidget);
      expect(find.text('RDV: 4'), findsOneWidget);
      expect(find.text('En attente: 2'), findsOneWidget);
      expect(find.text('Liste attente: 7'), findsOneWidget);
    });
  });
}
