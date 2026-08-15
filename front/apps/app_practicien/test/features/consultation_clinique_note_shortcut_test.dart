//! Tests widget : raccourci ⌘S de la note de séance (#4942, point 4 de la
//! maquette) — force l'enregistrement, l'auto-save restant en place ailleurs.

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
  note: 'Observation initiale',
);

void main() {
  late MockConsultationCliniqueBloc bloc;

  setUpAll(() {
    // `verifyNever(() => bloc.add(any()))` a besoin d'une valeur de repli pour
    // le type `ConsultationCliniqueEvent` (mocktail, null-safety).
    registerFallbackValue(const ConsultationCliniqueNoteSaveRequested(''));
  });

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
            child: SizedBox(
              width: 1400,
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

  testWidgets('badge ⌘S affiché à côté du bouton d\'enregistrement de la note',
      (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    expect(find.byKey(const Key('note_save_shortcut_badge')), findsOneWidget);
    expect(find.text('⌘S'), findsOneWidget);
    expect(find.byKey(const Key('save_note_button')), findsOneWidget);
  });

  testWidgets(
      '⌘S déclenche ConsultationCliniqueNoteSaveRequested avec le texte de la note',
      (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    await tester.enterText(
        find.byKey(const Key('consultation_note_field')), 'Note mise à jour');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    verify(() => bloc.add(
          const ConsultationCliniqueNoteSaveRequested('Note mise à jour'),
        )).called(1);
  });

  testWidgets('S sans ⌘ n\'enregistre pas la note', (tester) async {
    await _setSurface(tester);
    await tester.pumpWidget(buildBody());
    await tester.pump();

    await tester.tap(find.byKey(const Key('consultation_note_field')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.pump();

    // Aucune sauvegarde de note déclenchée par « S » seul (le
    // `ConsultationCliniqueLoadRequested` de l'`initState` n'est pas une
    // sauvegarde et ne doit pas faire échouer l'assertion).
    verifyNever(
      () => bloc.add(any(that: isA<ConsultationCliniqueNoteSaveRequested>())),
    );
  });
}
