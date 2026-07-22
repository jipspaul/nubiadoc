//! Tests widget : sélecteur de modèle de CR dans la note de séance (#4125).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
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

class MockListCrTemplatesUseCase extends Mock
    implements ListCrTemplatesUseCase {}

const _actDetartrage = ClinicalAct(
  id: 'act-1',
  ccamCode: 'HBLD001',
  label: 'Détartrage',
);

const _sessionNoActs = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
);

const _sessionWithAct = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [_actDetartrage],
);

const _matchingTemplate = CrTemplate(
  id: 'tmpl-1',
  ccamCode: 'HBLD001',
  title: 'CR détartrage',
  bodyTemplate: 'Détartrage réalisé sans complication.',
);

void main() {
  late MockConsultationCliniqueBloc bloc;
  late MockListCrTemplatesUseCase listCrTemplates;

  setUp(() {
    bloc = MockConsultationCliniqueBloc();
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
    final favoriteActs = MockFavoriteActsUseCase();
    when(() => favoriteActs.list()).thenAnswer((_) async => []);
    GetIt.instance.registerFactory<FavoriteActsUseCase>(() => favoriteActs);
    listCrTemplates = MockListCrTemplatesUseCase();
    GetIt.instance
        .registerFactory<ListCrTemplatesUseCase>(() => listCrTemplates);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<ConsultationCliniqueBloc>.value(
            value: bloc,
            child: const ConsultationCliniqueBody(consultationId: 's1'),
          ),
        ),
      );

  testWidgets(
      'sélection d\'un modèle correspondant au premier acte pré-remplit la note',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => bloc.state)
        .thenReturn(const ConsultationCliniqueLoaded(session: _sessionWithAct));
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: const ConsultationCliniqueLoaded(session: _sessionWithAct),
    );
    when(() => listCrTemplates.call())
        .thenAnswer((_) async => Right([_matchingTemplate]));

    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.tap(find.byKey(const Key('cr_template_picker_button')));
    await tester.pumpAndSettle();

    expect(find.text('Pour cet acte'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cr_template_tmpl-1')));
    await tester.pumpAndSettle();

    final noteField = tester
        .widget<TextField>(find.byKey(const Key('consultation_note_field')))
        .controller;
    expect(noteField?.text, 'Détartrage réalisé sans complication.');
  });

  testWidgets('aucun acte encore ajouté → picker sans groupe "Pour cet acte"',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => bloc.state)
        .thenReturn(const ConsultationCliniqueLoaded(session: _sessionNoActs));
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: const ConsultationCliniqueLoaded(session: _sessionNoActs),
    );
    when(() => listCrTemplates.call())
        .thenAnswer((_) async => Right([_matchingTemplate]));

    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.tap(find.byKey(const Key('cr_template_picker_button')));
    await tester.pumpAndSettle();

    expect(find.text('Pour cet acte'), findsNothing);
    expect(find.text('Autres modèles'), findsOneWidget);
  });
}
