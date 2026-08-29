import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/home_care/home_care_list_cubit.dart';
import 'package:app_patient/features/home_care/home_care_models.dart';
import 'package:app_patient/features/home_care/home_care_request_cubit.dart';
import 'package:app_patient/features/home_care/home_care_request_page.dart';
import 'package:app_patient/features/home_care/home_care_requests_page.dart';
import 'package:app_patient/features/home_care/home_care_tracking_cubit.dart';
import 'package:app_patient/features/home_care/home_care_tracking_page.dart';
import 'package:app_patient/session/auth_cubit.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

class MockHomeCareListCubit extends MockCubit<HomeCareListState>
    implements HomeCareListCubit {}

class MockHomeCareTrackingCubit extends MockCubit<HomeCareTrackingState>
    implements HomeCareTrackingCubit {}

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

const _visit = VisitRequest(
  id: 'visit-1',
  status: 'offered',
  requestedActs: ['pansement'],
  address: {'line1': '1 rue de Rivoli', 'city': 'Paris'},
  estimatedPriceCents: 4000,
);

Response<T> _fakeResponse<T>(T data) =>
    Response(data: data, requestOptions: RequestOptions(path: ''));

void main() {
  group('HomeCareRequestsBody', () {
    late MockHomeCareListCubit cubit;

    setUp(() {
      cubit = MockHomeCareListCubit();
    });

    testWidgets('état vide → NubiaEmptyState', (tester) async {
      when(() => cubit.state).thenReturn(const HomeCareListLoaded([]));

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: BlocProvider<HomeCareListCubit>.value(
          value: cubit,
          child: const HomeCareRequestsBody(),
        ),
      ));

      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });

    testWidgets('tap sur une demande → navigue vers /home-care/:id',
        (tester) async {
      when(() => cubit.state).thenReturn(const HomeCareListLoaded([_visit]));

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/home-care',
          routes: [
            GoRoute(
              path: '/home-care',
              builder: (_, __) => BlocProvider<HomeCareListCubit>.value(
                value: cubit,
                child: const HomeCareRequestsBody(),
              ),
            ),
            GoRoute(
              path: '/home-care/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('Suivi ${state.pathParameters['id']}')),
            ),
          ],
        ),
      ));

      await tester.tap(find.byKey(const Key('home_care_request_visit-1')));
      await tester.pumpAndSettle();

      expect(find.text('Suivi visit-1'), findsOneWidget);
    });

    testWidgets('tap sur le FAB → navigue vers /home-care/new', (tester) async {
      when(() => cubit.state).thenReturn(const HomeCareListLoaded([]));

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/home-care',
          routes: [
            GoRoute(
              path: '/home-care',
              builder: (_, __) => BlocProvider<HomeCareListCubit>.value(
                value: cubit,
                child: const HomeCareRequestsBody(),
              ),
            ),
            GoRoute(
              path: '/home-care/new',
              builder: (_, __) => const Scaffold(body: Text('Nouvelle demande')),
            ),
          ],
        ),
      ));

      await tester.tap(find.byKey(const Key('home_care_new_fab')));
      await tester.pumpAndSettle();

      expect(find.text('Nouvelle demande'), findsOneWidget);
    });
  });

  group('HomeCareTrackingBody', () {
    late MockHomeCareTrackingCubit cubit;

    setUp(() {
      cubit = MockHomeCareTrackingCubit();
    });

    Widget wrap() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<HomeCareTrackingCubit>.value(
            value: cubit,
            child: const HomeCareTrackingBody(),
          ),
        );

    testWidgets('statut annulable → bouton Annuler visible', (tester) async {
      when(() => cubit.state).thenReturn(const HomeCareTrackingLoaded(_visit));

      await tester.pumpWidget(wrap());

      expect(find.byKey(const Key('home_care_cancel_button')), findsOneWidget);
    });

    testWidgets('statut terminal (done) → pas de bouton Annuler',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const HomeCareTrackingLoaded(
          VisitRequest(
            id: 'visit-1',
            status: 'done',
            requestedActs: ['pansement'],
            address: {},
            estimatedPriceCents: 4000,
          ),
        ),
      );

      await tester.pumpWidget(wrap());

      expect(find.byKey(const Key('home_care_cancel_button')), findsNothing);
    });

    testWidgets('tap Annuler → appelle cubit.cancel()', (tester) async {
      when(() => cubit.state).thenReturn(const HomeCareTrackingLoaded(_visit));
      when(() => cubit.cancel()).thenAnswer((_) async {});

      await tester.pumpWidget(wrap());
      await tester.tap(find.byKey(const Key('home_care_cancel_button')));

      verify(() => cubit.cancel()).called(1);
    });
  });

  group('HomeCareRequestBody (parcours complet)', () {
    late MockApiClient apiClient;
    late MockDio dio;
    late MockAuthCubit authCubit;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
      authCubit = MockAuthCubit();
      when(() => authCubit.state).thenReturn(const AuthUnauthenticated());
    });

    testWidgets(
        'sélection d\'un acte → devis → confirmation → navigue vers le suivi',
        (tester) async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/account/visit-requests/estimate',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
          (_) async => _fakeResponse({'estimated_price_cents': 4000}));
      when(
        () => dio.post<Map<String, dynamic>>(
          '/account/visit-requests',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _fakeResponse({
            'id': 'visit-1',
            'status': 'offered',
            'requested_acts': ['pansement'],
            'address': {'line1': '1 rue de Rivoli', 'city': 'Paris'},
            'estimated_price_cents': 4000,
          }));

      await tester.pumpWidget(MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/home-care/new',
          routes: [
            GoRoute(
              path: '/home-care/new',
              builder: (_, __) => MultiBlocProvider(
                providers: [
                  BlocProvider<HomeCareRequestCubit>(
                    create: (_) => HomeCareRequestCubit(
                      apiClient,
                      currentPosition: () async => Position(
                        latitude: 48.865,
                        longitude: 2.321,
                        timestamp: DateTime(2026, 1, 1),
                        accuracy: 0,
                        altitude: 0,
                        altitudeAccuracy: 0,
                        heading: 0,
                        headingAccuracy: 0,
                        speed: 0,
                        speedAccuracy: 0,
                      ),
                    ),
                  ),
                  BlocProvider<AuthCubit>.value(value: authCubit),
                ],
                child: const HomeCareRequestBody(),
              ),
            ),
            GoRoute(
              path: '/home-care/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('Suivi ${state.pathParameters['id']}')),
            ),
          ],
        ),
      ));

      await tester.tap(find.byKey(const Key('home_care_act_pansement')));
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('home_care_estimate_button')),
      );
      await tester.tap(find.byKey(const Key('home_care_estimate_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home_care_estimate_price')), findsOneWidget);

      await tester.enterText(
          find.ancestor(
              of: find.text('Adresse'), matching: find.byType(TextField)),
          '1 rue de Rivoli');
      await tester.pump();
      await tester.enterText(
          find.ancestor(
              of: find.text('Code postal'), matching: find.byType(TextField)),
          '75001');
      await tester.pump();
      await tester.enterText(
          find.ancestor(
              of: find.text('Ville'), matching: find.byType(TextField)),
          'Paris');
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('home_care_submit_button')),
      );
      await tester.tap(find.byKey(const Key('home_care_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Suivi visit-1'), findsOneWidget);
    });
  });
}
