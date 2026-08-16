import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/appointments_bloc.dart';
import 'package:app_patient/features/appointments/appointments_event.dart';
import 'package:app_patient/features/appointments/appointments_page.dart';
import 'package:app_patient/features/appointments/appointments_state.dart';
import 'package:app_patient/session/auth_cubit.dart';

// ---------------------------------------------------------------------------
// #5359 — recherche web (maquette design-v2 patient-web-tunnel-reservation,
// écran « Recherche ») : au-delà de 960 px, la liste de résultats est
// accompagnée d'un panneau de filtres patient `.aside` (238 px), chaque
// option affichant son compteur de résultats.
// ---------------------------------------------------------------------------

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

const _authenticatedState = AuthAuthenticated(
  AuthSession(kind: UserKind.patient, userId: 'u1', accountId: 'acc-1'),
);

MockAuthCubit _makeAuthCubit() {
  final cubit = MockAuthCubit();
  when(() => cubit.state).thenReturn(_authenticatedState);
  whenListen(cubit, const Stream<AuthState>.empty(),
      initialState: _authenticatedState);
  return cubit;
}

final _now = DateTime.now();

// Un praticien par filtre en scope (#5359, point 6 verbatim) + un praticien
// « neutre » qui ne matche rien, pour distinguer les compteurs.
const _neutral = ProviderResult(
  id: 'p0',
  displayName: 'Dr Neutre',
  specialty: 'Dentiste',
);
final _providers = [
  _neutral,
  ProviderResult(
    id: 'p1',
    displayName: 'Dr Sous48h',
    specialty: 'Dentiste',
    nextSlotAt: _now.add(const Duration(hours: 10)),
  ),
  const ProviderResult(
    id: 'p2',
    displayName: 'Dr Secteur1',
    specialty: 'Dentiste',
    sector: '1',
  ),
  const ProviderResult(
    id: 'p3',
    displayName: 'Dr TiersPayant',
    specialty: 'Dentiste',
    tiersPayant: true,
  ),
];

Future<void> _pumpSearch(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  final bloc = _MockAppointmentsBloc();
  when(() => bloc.state).thenReturn(
    AppointmentsProvidersLoaded(providers: _providers, query: ''),
  );
  when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: NubiaTheme.light,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<AppointmentsBloc>.value(value: bloc),
        BlocProvider<AuthCubit>.value(value: _makeAuthCubit()),
      ],
      child: const Scaffold(body: AppointmentsPage()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('panneau de filtres patient .aside (#5359)', () {
    testWidgets(
      'rend les 4 groupes avec leurs options aux libellés exacts',
      (tester) async {
        await _pumpSearch(tester);

        final aside = find.byKey(const Key('provider_filters_aside'));
        expect(aside, findsOneWidget);

        for (final label in [
          'DISPONIBILITÉ',
          'CONSULTATION',
          'TARIFS',
          'ACCESSIBILITÉ',
        ]) {
          expect(find.descendant(of: aside, matching: find.text(label)),
              findsOneWidget);
        }
        for (final label in [
          'Sous 48 h',
          'Cette semaine',
          'Samedi',
          'Nouveaux patients',
          'Secteur 1',
          'Secteur 2',
          'Tiers payant',
          'Accès PMR',
        ]) {
          expect(find.descendant(of: aside, matching: find.text(label)),
              findsOneWidget,
              reason: '$label doit être rendu dans le panneau');
        }
      },
    );

    testWidgets('chaque option affiche son compteur de résultats à droite',
        (tester) async {
      await _pumpSearch(tester);

      // 1 seul praticien (Dr Sous48h) a un prochain créneau sous 48h.
      final under48hRow = find.byKey(const Key('filter_under48h'));
      expect(find.descendant(of: under48hRow, matching: find.text('1')),
          findsOneWidget);

      // Aucun praticien du jeu de test n'est en secteur 2 : compteur à 0,
      // l'option reste affichée avec son compteur réel (jamais masquée).
      final sector2Row = find.byKey(const Key('filter_sector2'));
      expect(find.descendant(of: sector2Row, matching: find.text('0')),
          findsOneWidget);

      final tiersPayantRow = find.byKey(const Key('filter_tiersPayant'));
      expect(find.descendant(of: tiersPayantRow, matching: find.text('1')),
          findsOneWidget);
    });

    testWidgets('cocher un filtre met à jour la liste des résultats',
        (tester) async {
      await _pumpSearch(tester);

      expect(find.byType(ProviderCard), findsNWidgets(_providers.length));

      await tester.tap(find.descendant(
        of: find.byKey(const Key('filter_sector1')),
        matching: find.byType(NubiaCheckbox),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ProviderCard), findsOneWidget);
      expect(find.text('Dr Secteur1'), findsOneWidget);
      expect(find.text('Dr Neutre'), findsNothing);

      // Décocher restaure la liste complète.
      await tester.tap(find.descendant(
        of: find.byKey(const Key('filter_sector1')),
        matching: find.byType(NubiaCheckbox),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ProviderCard), findsNWidgets(_providers.length));
    });

    testWidgets('en dessous du seuil web, le panneau ne s\'affiche pas',
        (tester) async {
      // Sous le seuil `_kFicheWebBreakpoint` (960) mais assez large pour ne
      // pas heurter les débordements connus de ProviderCard en dessous de
      // ~400 px (hors scope #5359) : seul le franchissement du seuil est
      // sous test ici.
      await _pumpSearch(tester, size: const Size(800, 900));

      expect(find.byKey(const Key('provider_filters_aside')), findsNothing);
    });
  });
}
