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
// #5360 — fiche praticien web (maquette design-v2 patient-web-tunnel-
// reservation, écran « Fiche praticien — l'agenda est le contenu
// principal ») : au-delà de 960 px, AppointmentsSlotsLoaded rend la fiche
// complète (hero + onglets + agenda semaine) plutôt que la liste mobile.
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

const _provider = ProviderResult(
  id: 'p1',
  displayName: 'Dr Amélie Rousseau',
  specialty: 'Chirurgien-dentiste',
  address: '12 rue de la Paix, 75002 Paris',
);

Slot _slot(String id, DateTime at, {bool isAvailable = true}) => Slot(
      id: id,
      cabinetId: 'cab-1',
      practitionerId: 'p1',
      startsAt: at,
      endsAt: at.add(const Duration(minutes: 30)),
      isAvailable: isAvailable,
    );

Future<void> _pumpFiche(
  WidgetTester tester,
  AppointmentsSlotsLoaded state, {
  Size size = const Size(1280, 900),
}) async {
  final bloc = _MockAppointmentsBloc();
  when(() => bloc.state).thenReturn(state);
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
  final today = DateTime.now();
  final day0 = DateTime(today.year, today.month, today.day);

  group('fiche praticien web (#5360)', () {
    testWidgets(
      'rend le hero (nom, sous-titre, tags, prochaine disponibilité)',
      (tester) async {
        await _pumpFiche(
          tester,
          AppointmentsSlotsLoaded(
            provider: _provider,
            slots: [_slot('s1', day0.add(const Duration(hours: 14, minutes: 30)))],
          ),
        );

        expect(find.byKey(const Key('fiche_praticien_web')), findsOneWidget);
        expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
        expect(find.text('Chirurgien-dentiste'), findsOneWidget);
        expect(find.text('Secteur 1 — tarifs conventionnés'), findsOneWidget);
        expect(find.text('Tiers payant'), findsOneWidget);
        expect(find.text('Nouveaux patients acceptés'), findsOneWidget);
        expect(find.text('Accès PMR'), findsOneWidget);
        expect(find.text('Carte bancaire'), findsOneWidget);
        expect(find.text('Prochaine disponibilité'), findsOneWidget);
        expect(
          find.text("Aujourd'hui, 14:30"),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'affiche les 4 onglets, « Prendre rendez-vous » actif par défaut',
      (tester) async {
        await _pumpFiche(
          tester,
          AppointmentsSlotsLoaded(provider: _provider, slots: const []),
        );

        final tabBar = find.byKey(const Key('fiche_tab_bar'));
        expect(
          find.descendant(of: tabBar, matching: find.text('Prendre rendez-vous')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tabBar, matching: find.text('Présentation')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tabBar, matching: find.text('Tarifs')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tabBar, matching: find.text('Horaires & accès')),
          findsOneWidget,
        );
        // Onglet actif par défaut : l'agenda (contenu de l'onglet 0) est
        // visible sans interaction.
        expect(find.text('Choisissez un créneau'), findsOneWidget);

        // Bascule d'onglet : le contenu change, l'agenda disparaît.
        await tester.tap(find.byKey(const Key('fiche_tab_1')));
        await tester.pumpAndSettle();
        expect(find.text('Choisissez un créneau'), findsNothing);
        expect(
          find.byKey(const Key('fiche_tab_placeholder_Présentation')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      "l'agenda affiche 6 colonnes-jour de créneaux réels, navigable",
      (tester) async {
        await _pumpFiche(
          tester,
          AppointmentsSlotsLoaded(
            provider: _provider,
            slots: [
              _slot('s1', day0.add(const Duration(hours: 9))),
              _slot('s2', day0.add(const Duration(days: 1, hours: 10))),
              _slot('s3', day0.add(const Duration(days: 10, hours: 11))),
            ],
          ),
        );

        expect(find.byKey(const Key('week_agenda')), findsOneWidget);
        expect(find.byType(SlotChip), findsNWidgets(2));
        expect(find.text('09:00'), findsOneWidget);
        expect(find.text('10:00'), findsOneWidget);
        // Créneau à J+10 hors de la fenêtre initiale (J .. J+5) : pas rendu.
        expect(find.text('11:00'), findsNothing);
        // Semaine précédente désactivée sur la première semaine (aujourd'hui).
        final prevButton =
            tester.widget<IconButton>(find.byKey(const Key('week_prev')));
        expect(prevButton.onPressed, isNull);

        // Navigation semaine suivante (J+6 .. J+11) : le créneau à J+10
        // entre dans la fenêtre affichée.
        await tester.tap(find.byKey(const Key('week_next')));
        await tester.pumpAndSettle();
        expect(find.text('11:00'), findsOneWidget);

        // Retour arrière possible.
        final prevButtonAfterNav =
            tester.widget<IconButton>(find.byKey(const Key('week_prev')));
        expect(prevButtonAfterNav.onPressed, isNotNull);
      },
    );

    testWidgets(
      'la sélection d\'un créneau déclenche AppointmentsSlotSelected',
      (tester) async {
        final slot = _slot('s1', day0.add(const Duration(hours: 9)));
        final bloc = _MockAppointmentsBloc();
        when(() => bloc.state).thenReturn(
          AppointmentsSlotsLoaded(provider: _provider, slots: [slot]),
        );
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

        tester.view.physicalSize = const Size(1280, 900);
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

        await tester.tap(find.text('09:00'));
        await tester.pumpAndSettle();

        verify(() => bloc.add(AppointmentsSlotSelected(slot))).called(1);
      },
    );

    testWidgets(
      'en dessous du seuil, conserve la liste mobile historique',
      (tester) async {
        await _pumpFiche(
          tester,
          AppointmentsSlotsLoaded(
            provider: _provider,
            slots: [_slot('s1', day0.add(const Duration(hours: 9)))],
          ),
          size: const Size(400, 800),
        );

        expect(find.byKey(const Key('fiche_praticien_web')), findsNothing);
        expect(find.byKey(const Key('slots_back')), findsOneWidget);
      },
    );
  });
}
