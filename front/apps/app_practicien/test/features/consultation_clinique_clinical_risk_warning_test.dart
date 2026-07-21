//! Tests widget : dialogue bloquant d'alerte clinique (#4057/#4058).

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
    GetIt.instance.registerFactory<GetActsUseCase>(() => MockGetActsUseCase());
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

  testWidgets('clinicalRiskWarning → dialogue bloquant affiché avec le message',
      (tester) async {
    // _LoadedView (contenu complet de la séance) déborde à la taille de test
    // par défaut — sans rapport avec le dialogue testé ici.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => bloc.state).thenReturn(const ConsultationCliniqueLoaded(
      session: _session,
    ));
    whenListen(
      bloc,
      Stream.fromIterable([
        const ConsultationCliniqueLoaded(
          session: _session,
          clinicalRiskWarning:
              'Patient sous anticoagulants — vérifier le risque hémorragique.',
        ),
      ]),
      initialState: const ConsultationCliniqueLoaded(session: _session),
    );

    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(
      find.byKey(const Key('clinical_risk_warning_dialog')),
      findsOneWidget,
    );
    expect(
      find.text(
          'Patient sous anticoagulants — vérifier le risque hémorragique.'),
      findsOneWidget,
    );
  });

  testWidgets('« Compris » ferme le dialogue et consomme l\'alerte',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => bloc.state).thenReturn(const ConsultationCliniqueLoaded(
      session: _session,
    ));
    whenListen(
      bloc,
      Stream.fromIterable([
        const ConsultationCliniqueLoaded(
          session: _session,
          clinicalRiskWarning: 'Patient sous anticoagulants.',
        ),
      ]),
      initialState: const ConsultationCliniqueLoaded(session: _session),
    );

    await tester.pumpWidget(buildPage());
    await tester.pump();
    expect(
      find.byKey(const Key('clinical_risk_warning_dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('clinical_risk_warning_dismiss')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('clinical_risk_warning_dialog')),
      findsNothing,
    );
    verify(() =>
            bloc.add(const ConsultationCliniqueClinicalRiskWarningConsumed()))
        .called(1);
  });
}
