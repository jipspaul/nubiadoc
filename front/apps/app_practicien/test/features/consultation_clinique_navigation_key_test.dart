import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/consultation_clinique_bloc.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_event.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_page.dart';
import 'package:app_practicien/features/consultation_clinique/consultation_clinique_state.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockConsultationCliniqueBloc
    extends MockBloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    implements ConsultationCliniqueBloc {}

class MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

// ---------------------------------------------------------------------------
// Tests — #6190 : cliquer une carte de l'historique doit rouvrir la
// séance même quand go_router réutilise le même State (navigation
// /consultation -> /consultation?id=X sans démonter l'arbre).
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
      'ConsultationCliniquePage recharge la séance quand consultationId '
      'change sans que le widget parent soit démonté', (tester) async {
    final bloc = MockConsultationCliniqueBloc();
    when(() => bloc.state).thenReturn(
      const ConsultationHistoriqueLoaded(sessions: []),
    );

    final authCubit = MockProAuthCubit();
    when(() => authCubit.state).thenReturn(
      const AuthAuthenticated(
        AuthSession(
          kind: UserKind.pro,
          userId: 'prac-1',
          role: ProRole.practitioner,
        ),
      ),
    );

    // #6263 — ConsultationCliniquePage résout la cloche de notifications de
    // ProShell via GetIt.
    final notificationRepository = MockNotificationRepository();
    when(() => notificationRepository.getNotifications(unreadOnly: true))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<NotificationRepository>(() => notificationRepository);
    addTearDown(GetIt.instance.reset);

    Widget buildPage(String? consultationId) => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<ProAuthCubit>.value(
            value: authCubit,
            child: BlocProvider<ConsultationCliniqueBloc>.value(
              value: bloc,
              child: ConsultationCliniquePage(consultationId: consultationId),
            ),
          ),
        );

    // 1) Chargement initial de la vue Historique (sans id dans l'URL).
    await tester.pumpWidget(buildPage(null));
    await tester.pump();
    verify(() => bloc.add(const ConsultationHistoriqueRequested())).called(1);

    // 2) go_router navigue vers /consultation?id=abc123 : le même
    // MaterialApp reste monté, seul le paramètre consultationId change —
    // exactement le scénario du bug (l'URL change, l'arbre ne se démonte
    // pas). Sans Key dérivée de consultationId, ce second pumpWidget ne
    // déclencherait jamais ConsultationCliniqueLoadRequested.
    await tester.pumpWidget(buildPage('abc123'));
    await tester.pump();

    verify(() => bloc.add(const ConsultationCliniqueLoadRequested('abc123')))
        .called(1);
  });
}
