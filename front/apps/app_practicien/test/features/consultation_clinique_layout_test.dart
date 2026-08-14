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
  Widget buildBodyAtWidth(double width) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: SizedBox(
              width: width,
              height: 900,
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
}
