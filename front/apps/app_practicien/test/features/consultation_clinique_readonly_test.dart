//! Tests widget : séance `completed`/`cancelled` → la colonne de saisie
//! (CCAM/favoris, note) passe en lecture seule au lieu de laisser
//! l'utilisateur aboutir à un 409 `invalid_status` (#8589).

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

const _finishedSession = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'completed',
  acts: [],
  note: 'Observation initiale',
);

const _ongoingSession = ClinicalSession(
  id: 's2',
  appointmentId: 'a2',
  status: 'in_progress',
  acts: [],
  note: 'Observation initiale',
);

void main() {
  late MockConsultationCliniqueBloc bloc;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildBody(ClinicalSession session) {
    when(() => bloc.state)
        .thenReturn(ConsultationCliniqueLoaded(session: session));
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: ConsultationCliniqueLoaded(session: session),
    );
    return MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<ConsultationCliniqueBloc>.value(
          value: bloc,
          child: SizedBox(
            width: 1400,
            height: 900,
            child: ConsultationCliniqueBody(consultationId: session.id),
          ),
        ),
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'séance completed → recherche CCAM désactivée et note en lecture seule',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(buildBody(_finishedSession));
    await tester.pump();

    final searchField = tester.widget<TextField>(find.descendant(
      of: find.byKey(const Key('ccam_search_field')),
      matching: find.byType(TextField),
    ));
    expect(searchField.enabled, isFalse);

    final noteField = tester.widget<TextField>(
      find.byKey(const Key('consultation_note_field')),
    );
    expect(noteField.readOnly, isTrue);

    final crTemplateButton = tester.widget<TextButton>(
      find.byKey(const Key('cr_template_picker_button')),
    );
    expect(crTemplateButton.onPressed, isNull);
  });

  testWidgets(
      'séance in_progress → recherche CCAM et note restent actives (contre-épreuve)',
      (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(buildBody(_ongoingSession));
    await tester.pump();

    final searchField = tester.widget<TextField>(find.descendant(
      of: find.byKey(const Key('ccam_search_field')),
      matching: find.byType(TextField),
    ));
    expect(searchField.enabled, isTrue);

    final noteField = tester.widget<TextField>(
      find.byKey(const Key('consultation_note_field')),
    );
    expect(noteField.readOnly, isFalse);
  });
}
