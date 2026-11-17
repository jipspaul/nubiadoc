//! Tests widget : séance `in_progress` d'un CONFRÈRE (même cabinet) → la
//! colonne de saisie (CCAM/favoris, note) passe en lecture seule et
//! « Terminer la séance » est désactivé, au lieu de laisser l'utilisateur
//! aboutir aux 3 gardes serveur en 403 (#8664, même traitement que #8589
//! pour `isFinished`).

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

const _foreignSession = ClinicalSession(
  id: 's1',
  appointmentId: 'a1',
  status: 'in_progress',
  acts: [],
  note: null,
  practitionerName: 'Dr Claire Lefèvre',
  practitionerId: 'c0000000-0000-0000-0000-0000000000c2',
);

const _ownSession = ClinicalSession(
  id: 's2',
  appointmentId: 'a2',
  status: 'in_progress',
  acts: [],
  note: 'Observation initiale',
  practitionerName: 'Dr Hugo Marin',
  practitionerId: 'c0000000-0000-0000-0000-0000000000c1',
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

  Widget buildBody(ClinicalSession session, {required bool isForeignSession}) {
    final state = ConsultationCliniqueLoaded(
      session: session,
      isForeignSession: isForeignSession,
    );
    when(() => bloc.state).thenReturn(state);
    whenListen(
      bloc,
      const Stream<ConsultationCliniqueState>.empty(),
      initialState: state,
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
      'séance in_progress d\'un confrère → recherche CCAM désactivée, note en lecture seule, '
      '« Terminer la séance » désactivé', (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(
      buildBody(_foreignSession, isForeignSession: true),
    );
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

    final completeButton = tester.widget<NubiaButton>(
      find.byKey(const Key('complete_consultation_button')),
    );
    expect(completeButton.onPressed, isNull);
  });

  testWidgets(
      'séance in_progress du praticien connecté → recherche CCAM et note restent actives '
      '(contre-épreuve)', (tester) async {
    await setSurface(tester);
    await tester.pumpWidget(
      buildBody(_ownSession, isForeignSession: false),
    );
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

    final completeButton = tester.widget<NubiaButton>(
      find.byKey(const Key('complete_consultation_button')),
    );
    expect(completeButton.onPressed, isNotNull);
  });
}
