//! Tests widget : pastille « Dent NN sélectionnée » du panneau « Ajouter un
//! acte » (#4959, point 2 de la maquette design-v2).

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

  // Largeur ≥ 900 px : colonnes centre + saisie visibles côte à côte, sans
  // passer par le layout 1 colonne (SingleChildScrollView) qui compliquerait
  // le scroll jusqu'à la pastille dans le test.
  Widget buildBody() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: const SizedBox(
              width: 1000,
              height: 900,
              child: ConsultationCliniqueBody(consultationId: 's1'),
            ),
          ),
        ),
      );

  Future<void> setSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('aucune dent sélectionnée → pas de pastille', (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected_tooth_pill')), findsNothing);
    expect(find.byKey(const Key('act_tooth_picker_clear')), findsNothing);
  });

  testWidgets(
      'tap sur une dent → pastille « Dent 11 sélectionnée » visible en tête du panneau',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('consultation_tooth_11')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected_tooth_pill')), findsOneWidget);
    expect(find.text('Dent 11 sélectionnée'), findsOneWidget);
    expect(find.byKey(const Key('act_tooth_picker_clear')), findsOneWidget);
  });

  testWidgets(
      'la croix (act_tooth_picker_clear) efface la sélection et masque la pastille',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('consultation_tooth_11')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected_tooth_pill')), findsOneWidget);

    await tester.tap(find.byKey(const Key('act_tooth_picker_clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected_tooth_pill')), findsNothing);
    expect(find.byKey(const Key('act_tooth_picker_clear')), findsNothing);
    // La dent 11 n'est plus sélectionnée dans le schéma dentaire non plus.
    expect(find.byKey(const Key('consultation_tooth_11')), findsOneWidget);
  });
}
