// Issue #6448 — l'onglet « Historique » affichait un compteur « 0 » à
// l'arrivée sur l'écran (avant que l'historique n'ait été chargé), alors que
// le patient a un historique réel. Le compteur ne doit jamais mentir : il
// reste masqué tant que `historyLoaded` est faux, et la liste montre un
// squelette (pas un « Aucun historique » trompeur) pendant le chargement.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_page.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

class _MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const MesRdvLoadRequested());
  });

  late _MockMesRdvBloc mockBloc;
  late SemanticsHandle semantics;

  setUp(() async {
    mockBloc = _MockMesRdvBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<MesRdvBloc>(() => mockBloc);
    semantics = SemanticsBinding.instance.ensureSemantics();
  });

  tearDown(() async {
    semantics.dispose();
    await GetIt.instance.reset();
  });

  Appointment apptAt(String id, DateTime startsAt) => Appointment(
        id: id,
        cabinetId: 'cab-1',
        practitionerName: 'Dr Lemaire',
        practitionerSpecialty: 'Dentiste',
        startsAt: startsAt,
        duration: const Duration(minutes: 30),
        motif: 'Contrôle',
        status: AppointmentStatus.completed,
      );

  Future<void> pump(
    WidgetTester tester,
    MesRdvState state, {
    bool settle = true,
  }) async {
    whenListen(
      mockBloc,
      Stream<MesRdvState>.fromIterable([state]).asBroadcastStream(),
      initialState: state,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: MesRdvPage()),
      ),
    );
    // #6448 : le squelette de chargement porte une animation shimmer en
    // boucle infinie — `pumpAndSettle` ne se termine jamais tant qu'elle
    // tourne (cf. mes_rdv_skeleton_empty_test.dart, même contrainte).
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
      'historique non chargé (historyLoaded=false) : le compteur est masqué, '
      'pas de faux "0"', (tester) async {
    final state = MesRdvLoaded(
      upcoming: [apptAt('rdv-1', DateTime.now().add(const Duration(days: 2)))],
      history: const [],
    );
    await pump(tester, state);

    expect(find.text('Historique'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Historique \(\d')), findsNothing);
  });

  testWidgets(
      'historique chargé (historyLoaded=true) : le compteur reflète le total réel',
      (tester) async {
    final history = [
      apptAt('rdv-1', DateTime(2026, 7, 10, 9)),
      apptAt('rdv-2', DateTime(2026, 7, 3, 9)),
      apptAt('rdv-3', DateTime(2026, 6, 15, 9)),
    ];
    final state = MesRdvLoaded(
      upcoming: const [],
      history: history,
      historyLoaded: true,
    );
    await pump(tester, state);

    expect(find.bySemanticsLabel(RegExp(r'Historique \(3\)')), findsOneWidget);
  });

  testWidgets(
      'historique en cours de chargement : squelette affiché, pas '
      '"Aucun historique"', (tester) async {
    final state = MesRdvLoaded(
      upcoming: const [],
      history: const [],
      historyLoading: true,
    );
    await pump(tester, state, settle: false);

    // #6448 : IndexedStack masque des finders les enfants hors-écran par
    // défaut (`skipOffstage`) — il faut basculer sur l'onglet Historique
    // pour que son contenu devienne l'enfant actif et donc trouvable.
    await tester.tap(find.text('Historique'));
    await tester.pump();

    expect(find.byKey(const Key('history_loading')), findsOneWidget);
    expect(find.byKey(const Key('empty_history')), findsNothing);
  });

  testWidgets(
      'erreur de chargement historique : état d\'erreur affiché, pas '
      '"Aucun historique"', (tester) async {
    final state = MesRdvLoaded(
      upcoming: const [],
      history: const [],
      historyError: 'Erreur de chargement.',
    );
    await pump(tester, state);

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history_error')), findsOneWidget);
    expect(find.text('Erreur de chargement.'), findsOneWidget);
    expect(find.byKey(const Key('empty_history')), findsNothing);
  });
}
