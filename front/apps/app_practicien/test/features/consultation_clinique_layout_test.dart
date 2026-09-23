//! Tests widget : layout 3 colonnes responsive de la consultation (#4935).
//! Les seuils sont décidés par un LayoutBuilder sur la largeur disponible,
//! jamais MediaQuery — voir consultation_clinique_page.dart.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/ccam_picker.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_page.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockGetActsUseCase extends Mock implements GetActsUseCase {}

class MockFavoriteActsUseCase extends Mock implements FavoriteActsUseCase {}

const _session = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
);

void main() {
  late MockConsultationCliniqueBloc bloc;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    when(() => bloc.state)
        .thenReturn(const ConsultationCliniqueLoaded(session: _session));
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: const ConsultationCliniqueLoaded(session: _session),
    );
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    addTearDown(GetIt.instance.reset);
  });

  // La largeur *disponible* du corps (pas la fenêtre) pilote le LayoutBuilder
  // : on la fixe via un SizedBox ancêtre plutôt que via MediaQuery/physicalSize.
  Widget buildBodyAtWidth(double width, {double height = 900}) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: SizedBox(
              width: width,
              height: height,
              child: const ConsultationCliniqueBody(consultationId: 's1'),
            ),
          ),
        ),
      );

  Future<void> _setSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('≥ 1280 px : les trois zones (contexte/centre/saisie) sont visibles',
      (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBodyAtWidth(1400));
    await tester.pump();

    expect(find.byKey(const Key('consultation_context_panel')), findsOneWidget);
    expect(find.byKey(const Key('consultation_center_panel')), findsOneWidget);
    expect(find.byKey(const Key('consultation_side_panel')), findsOneWidget);
    expect(find.byKey(const Key('consultation_single_column')), findsNothing);
  });

  testWidgets('900–1279 px : la colonne de contexte est absente', (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBodyAtWidth(1100));
    await tester.pump();

    expect(find.byKey(const Key('consultation_context_panel')), findsNothing);
    expect(find.byKey(const Key('consultation_center_panel')), findsOneWidget);
    expect(find.byKey(const Key('consultation_side_panel')), findsOneWidget);
    expect(find.byKey(const Key('consultation_single_column')), findsNothing);
  });

  testWidgets('< 900 px : une seule colonne défilante', (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBodyAtWidth(800));
    await tester.pump();

    expect(find.byKey(const Key('consultation_context_panel')), findsNothing);
    expect(find.byKey(const Key('consultation_single_column')), findsOneWidget);
    expect(find.byKey(const Key('consultation_center_panel')), findsOneWidget);
    expect(find.byKey(const Key('consultation_side_panel')), findsOneWidget);
  });

  testWidgets(
      '≥ 1280 px, hauteur très réduite : le champ « Note de séance » garde '
      'un plancher lisible au lieu d\'être écrasé sous une ligne (#7529)',
      (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBodyAtWidth(1400, height: 300));
    await tester.pump();

    final noteFieldHeight =
        tester.getSize(find.byKey(const Key('consultation_note_field'))).height;
    // Avant #7529, un partage figé 3:1 avec « Ajouter un acte » donnait à la
    // note exactement 1/4 de la hauteur disponible, quel que soit le besoin
    // réel du panneau d'ajout (~23 px observés à 1280×800) : moins qu'une
    // seule ligne de texte. La note doit maintenant primer sur ce panneau.
    expect(noteFieldHeight, greaterThanOrEqualTo(40));
    // « Ajouter un acte » reste dans l'arbre (défile/se réduit au besoin) —
    // il ne doit pas planter ni disparaître.
    expect(find.byKey(const Key('ccam_picker')), findsOneWidget);
  });

  testWidgets(
      '≥ 1280 px, hauteur confortable : « Ajouter un acte » ne monopolise '
      'plus un partage figé quand son contenu est modeste (#7529)',
      (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBodyAtWidth(1400, height: 500));
    await tester.pump();

    final noteFieldHeight =
        tester.getSize(find.byKey(const Key('consultation_note_field'))).height;
    // Avant #7529 (partage figé 3:1), la note aurait été plafonnée à ~1/4 de
    // la hauteur disponible même avec un panneau d'ajout au contenu minime
    // (aucun favori ici). Elle doit désormais absorber l'essentiel de
    // l'espace que « Ajouter un acte » n'utilise pas.
    expect(noteFieldHeight, greaterThanOrEqualTo(150));
  });
}
