//! Test widget : total de séance affiché dans la barre patient (#4946).
//! Libellé « TOTAL SÉANCE » + montant, cohérent avec la somme des
//! `amountCents` des actes enregistrés (#3402).

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
  acts: [
    ClinicalAct(
      id: 'act1',
      ccamCode: 'HBGD036',
      label: 'Détartrage deux arcades',
      amountCents: 100000,
    ),
    ClinicalAct(
      id: 'act2',
      ccamCode: 'HBMD028',
      label: 'Soin conservateur',
      amountCents: 46000,
    ),
  ],
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

  testWidgets(
      'la barre patient affiche « TOTAL SÉANCE » et la somme des montants des actes',
      (tester) async {
    await tester.pumpWidget(buildBody());
    await tester.pump();

    final totalFinder = find.byKey(const Key('consultation_session_total'));
    expect(totalFinder, findsOneWidget);
    expect(
      find.descendant(of: totalFinder, matching: find.text('TOTAL SÉANCE')),
      findsOneWidget,
    );
    // 100000 + 46000 = 146000 centimes = 1 460 €.
    expect(
      find.descendant(
          of: totalFinder, matching: find.text(formatQuoteCents(146000))),
      findsOneWidget,
    );
  });
}
