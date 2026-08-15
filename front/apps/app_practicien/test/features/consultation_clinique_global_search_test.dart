//! Test widget : recherche globale de la barre du haut (#4948).
//! Champ « Acte, patient, ordonnance… » + badge ⌘K, centré entre l'identité
//! patient et le total — partage le focus avec la recherche d'acte CCAM du
//! volet droit (pas de recherche transverse pour l'instant, cf. #4941).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Widget buildBody() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: const ConsultationCliniqueBody(consultationId: 's1'),
          ),
        ),
      );

  // Largeur ≥ 900 px (`_kTwoColumnBreakpoint`) requise pour afficher la
  // recherche globale sans écraser l'identité patient (#4948).
  Future<void> setWideSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'la barre du haut affiche le champ « Acte, patient, ordonnance… » '
      'avec icône loupe et badge ⌘K', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    final fieldFinder = find.byKey(const Key('global_search_field'));
    expect(fieldFinder, findsOneWidget);
    expect(
      find.descendant(of: fieldFinder, matching: find.byIcon(Icons.search)),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: fieldFinder, matching: find.text('Acte, patient, ordonnance…')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fieldFinder, matching: find.text('⌘K')),
      findsOneWidget,
    );
  });

  testWidgets(
      'le champ de recherche globale est positionné entre l\'identité '
      'patient et le total', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    final identityX = tester.getCenter(find.byType(NubiaAvatar)).dx;
    final searchX =
        tester.getCenter(find.byKey(const Key('global_search_field'))).dx;
    final totalX = tester
        .getCenter(find.byKey(const Key('consultation_session_total')))
        .dx;

    expect(searchX, greaterThan(identityX));
    expect(totalX, greaterThan(searchX));
  });

  testWidgets(
      'tap sur la recherche globale place le focus sur la recherche '
      'd\'acte CCAM (#4948, périmètre limité tant qu\'il n\'existe pas de '
      'recherche transverse)', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    await tester.tap(find.byKey(const Key('global_search_field')));
    await tester.pumpAndSettle();

    final focusNode = tester
        .widget<TextField>(find.descendant(
          of: find.byKey(const Key('ccam_search_field')),
          matching: find.byType(TextField),
        ))
        .focusNode;
    expect(focusNode?.hasFocus, isTrue);
  });

  testWidgets(
      '⌘K depuis la barre du haut active aussi la recherche d\'acte CCAM '
      '(cohérence avec #4941)', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    final focusNode = tester
        .widget<TextField>(find.descendant(
          of: find.byKey(const Key('ccam_search_field')),
          matching: find.byType(TextField),
        ))
        .focusNode;
    expect(focusNode?.hasFocus, isTrue);
  });
}
