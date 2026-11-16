// Régression #8624 : sélectionner un onglet de la barre du bas (Mes RDV,
// Documents, ...) ne mutait qu'un index local (`setState`) sans jamais
// appeler `context.go` — l'URL restait sur `/` quel que soit l'onglet
// affiché. Un F5 perdait alors silencieusement l'onglet (retour sur
// Accueil) et le bouton Retour du navigateur ne pouvait pas en sortir.
// Même classe de défaut que #8620, déjà corrigée pour le spotlight
// secrétariat.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_event.dart';
import 'package:app_patient/features/documents/documents_state.dart';
import 'package:app_patient/features/home/home_bloc.dart';
import 'package:app_patient/features/home/home_event.dart';
import 'package:app_patient/features/home/home_state.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';
import 'package:app_patient/features/messaging/messaging_bloc.dart';
import 'package:app_patient/features/messaging/messaging_event.dart';
import 'package:app_patient/features/messaging/messaging_state.dart';
import 'package:app_patient/features/notifications/notifications_bloc.dart';
import 'package:app_patient/features/notifications/notifications_event.dart';
import 'package:app_patient/features/notifications/notifications_state.dart';
import 'package:app_patient/router/app_router.dart';
import 'package:app_patient/session/auth_cubit.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

class _MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState>
    implements HomeBloc {}

class _MockMessagingBloc extends MockBloc<MessagingEvent, MessagingState>
    implements MessagingBloc {}

class _MockNotificationsBloc
    extends MockBloc<NotificationsEvent, NotificationsState>
    implements NotificationsBloc {}

class _MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

class _MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

void main() {
  setUp(() {
    GetIt.instance
      ..registerFactory<HomeBloc>(() {
        final bloc = _MockHomeBloc();
        when(() => bloc.state).thenReturn(const HomeLoaded(
          DashboardSummary(
            upcomingAppointments: 0,
            documentsToSign: 0,
            pendingPaymentsCents: 0,
            unreadMessages: 0,
          ),
        ));
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        return bloc;
      })
      ..registerFactory<MessagingBloc>(() {
        final bloc = _MockMessagingBloc();
        when(() => bloc.state)
            .thenReturn(const MessagingConversationsLoaded([]));
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        return bloc;
      })
      ..registerFactory<NotificationsBloc>(() {
        final bloc = _MockNotificationsBloc();
        when(() => bloc.state).thenReturn(const NotificationsInitial());
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        return bloc;
      })
      ..registerFactory<DocumentsBloc>(() {
        final bloc = _MockDocumentsBloc();
        when(() => bloc.state).thenReturn(const DocumentsLoaded([]));
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        return bloc;
      })
      ..registerFactory<MesRdvBloc>(() {
        final bloc = _MockMesRdvBloc();
        when(() => bloc.state)
            .thenReturn(const MesRdvLoaded(upcoming: [], history: []));
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        return bloc;
      });
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
    'taper l\'onglet Documents pousse /documents (URL suit l\'onglet, '
    'pas seulement un état local)',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go(AppRouter.home);

      final authCubit = _MockAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(AuthSession(
          kind: UserKind.patient,
          userId: 'patient-marc',
          displayName: 'Marc Dubois',
        )),
      );
      when(() => authCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.home,
      );

      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.documents,
      );

      // Taper Accueil depuis la barre de la route /documents (#8624 : cette
      // route porte désormais la même barre que le shell) doit revenir sur
      // /, pas rester bloqué faute de barre de navigation.
      await tester.tap(find.text('Accueil'));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.home,
      );
    },
  );

  testWidgets(
    'taper l\'onglet Mes RDV pousse /mes-rdv (même règle)',
    (tester) async {
      final notifier = RouterNotifier(MockTokenStorage())..markAuthenticated();
      final router = AppRouter.create(notifier);
      router.go(AppRouter.home);

      final authCubit = _MockAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(AuthSession(
          kind: UserKind.patient,
          userId: 'patient-marc',
          displayName: 'Marc Dubois',
        )),
      );
      when(() => authCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mes RDV'));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.toString(),
        AppRouter.mesRdv,
      );
    },
  );
}
