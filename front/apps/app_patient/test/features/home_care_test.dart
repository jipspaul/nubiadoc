import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';

import 'package:app_patient/features/home_care/home_care_list_cubit.dart';
import 'package:app_patient/features/home_care/home_care_models.dart';
import 'package:app_patient/features/home_care/home_care_request_cubit.dart';
import 'package:app_patient/features/home_care/home_care_tracking_cubit.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

// Le patient est place Concorde, Paris — coordonnées arbitraires cohérentes
// avec `ALLOWED_ACTS`/`estimate_price_cents` côté back (api/src/nurse).
final _fakePosition = Position(
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
);

Response<T> _fakeResponse<T>(T data) =>
    Response(data: data, requestOptions: RequestOptions(path: ''));

void main() {
  late MockApiClient apiClient;
  late MockDio dio;

  setUp(() {
    apiClient = MockApiClient();
    dio = MockDio();
    when(() => apiClient.dio).thenReturn(dio);
  });

  group('HomeCareRequestCubit.estimate', () {
    blocTest<HomeCareRequestCubit, HomeCareRequestState>(
      'POST /account/visit-requests/estimate → [Estimating, Estimated]',
      setUp: () {
        when(
          () => dio.post<Map<String, dynamic>>(
            '/account/visit-requests/estimate',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
            (_) async => _fakeResponse({'estimated_price_cents': 4000}));
      },
      build: () => HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => _fakePosition,
      ),
      act: (cubit) => cubit.estimate(['pansement', 'prise_de_sang']),
      expect: () => [
        const HomeCareRequestEstimating(),
        const HomeCareRequestEstimated(4000),
      ],
    );

    test('aucun acte sélectionné → reste Idle sans appel réseau', () async {
      final cubit = HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => _fakePosition,
      );

      await cubit.estimate(const []);

      verifyNever(() => dio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
          ));
      expect(cubit.state, const HomeCareRequestIdle());
    });

    test('position indisponible → Failure explicite', () async {
      final cubit = HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => null,
      );

      await cubit.estimate(['pansement']);

      expect(cubit.state, isA<HomeCareRequestFailure>());
      verifyNever(() => dio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
          ));
    });

    test('422 (acte invalide) → message dédié', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/account/visit-requests/estimate',
          data: any(named: 'data'),
        ),
      ).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 422,
          requestOptions: RequestOptions(path: ''),
        ),
      ));

      final cubit = HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => _fakePosition,
      );

      await cubit.estimate(['pansement']);

      expect(
        (cubit.state as HomeCareRequestFailure).message,
        'Actes ou coordonnées invalides.',
      );
    });

    test('resetEstimate invalide un devis affiché', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/account/visit-requests/estimate',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
          (_) async => _fakeResponse({'estimated_price_cents': 4000}));

      final cubit = HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => _fakePosition,
      );
      await cubit.estimate(['pansement']);
      expect(cubit.state, isA<HomeCareRequestEstimated>());

      cubit.resetEstimate();

      expect(cubit.state, const HomeCareRequestIdle());
    });
  });

  group('HomeCareRequestCubit.submit', () {
    blocTest<HomeCareRequestCubit, HomeCareRequestState>(
      'POST /account/visit-requests → [Submitting, Created]',
      setUp: () {
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
      },
      build: () => HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => _fakePosition,
      ),
      act: (cubit) => cubit.submit(
        acts: const ['pansement'],
        line1: '1 rue de Rivoli',
        city: 'Paris',
        postalCode: '75001',
        patientDisplayName: 'Marc D.',
      ),
      expect: () => [
        const HomeCareRequestSubmitting(),
        isA<HomeCareRequestCreated>()
            .having((s) => s.visit.id, 'visit.id', 'visit-1')
            .having((s) => s.visit.status, 'visit.status', 'offered'),
      ],
    );

    test('409 (demande déjà active) → message dédié', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/account/visit-requests',
          data: any(named: 'data'),
        ),
      ).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 409,
          requestOptions: RequestOptions(path: ''),
        ),
      ));

      final cubit = HomeCareRequestCubit(
        apiClient,
        currentPosition: () async => _fakePosition,
      );

      await cubit.submit(
        acts: const ['pansement'],
        line1: '1 rue de Rivoli',
        city: 'Paris',
        postalCode: '75001',
        patientDisplayName: 'Marc D.',
      );

      expect(
        (cubit.state as HomeCareRequestFailure).message,
        'Une demande de visite est déjà en cours.',
      );
    });
  });

  group('HomeCareListCubit.load', () {
    test('GET /account/visit-requests → Loaded(requests)', () async {
      when(() => dio.get<List<dynamic>>('/account/visit-requests'))
          .thenAnswer((_) async => _fakeResponse([
                {
                  'id': 'visit-1',
                  'status': 'done',
                  'requested_acts': ['prise_de_sang'],
                  'address': <String, dynamic>{},
                  'estimated_price_cents': 2000,
                },
              ]));

      final cubit = HomeCareListCubit(apiClient);
      await cubit.load();

      expect(
        cubit.state,
        isA<HomeCareListLoaded>().having(
          (s) => s.requests.single.id,
          'requests.single.id',
          'visit-1',
        ),
      );
    });

    test('erreur réseau → HomeCareListError', () async {
      when(() => dio.get<List<dynamic>>('/account/visit-requests'))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '')));

      final cubit = HomeCareListCubit(apiClient);
      await cubit.load();

      expect(cubit.state, isA<HomeCareListError>());
    });
  });

  group('HomeCareTrackingCubit', () {
    Map<String, dynamic> visitJson(String status) => {
          'id': 'visit-1',
          'status': status,
          'requested_acts': ['pansement'],
          'address': {'line1': 'Rue A', 'city': 'Paris'},
          'estimated_price_cents': 4000,
        };

    test('load() → Loaded(visit)', () async {
      when(() => dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
          .thenAnswer((_) async => _fakeResponse(visitJson('accepted')));

      final cubit = HomeCareTrackingCubit(apiClient);
      await cubit.load('visit-1');

      expect(
        cubit.state,
        isA<HomeCareTrackingLoaded>()
            .having((s) => s.visit.status, 'visit.status', 'accepted'),
      );
    });

    test('cancel() → renvoie la visite annulée', () async {
      when(() => dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
          .thenAnswer((_) async => _fakeResponse(visitJson('offered')));
      when(() => dio.post<Map<String, dynamic>>(
            '/account/visit-requests/visit-1/cancel',
          )).thenAnswer((_) async => _fakeResponse(visitJson('cancelled')));

      final cubit = HomeCareTrackingCubit(apiClient);
      await cubit.load('visit-1');
      await cubit.cancel();

      expect(
        cubit.state,
        isA<HomeCareTrackingLoaded>()
            .having((s) => s.visit.status, 'visit.status', 'cancelled')
            .having((s) => s.cancelling, 'cancelling', false),
      );
    });

    test('cancel() sur 409 → HomeCareTrackingError dédié', () async {
      when(() => dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
          .thenAnswer((_) async => _fakeResponse(visitJson('done')));
      when(() => dio.post<Map<String, dynamic>>(
            '/account/visit-requests/visit-1/cancel',
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 409,
          requestOptions: RequestOptions(path: ''),
        ),
      ));

      final cubit = HomeCareTrackingCubit(apiClient);
      await cubit.load('visit-1');
      await cubit.cancel();

      expect(
        (cubit.state as HomeCareTrackingError).message,
        'Cette demande ne peut plus être annulée.',
      );
    });
  });

  group('VisitRequest.fromJson', () {
    test('adresse absente → map vide, pas de crash', () {
      final visit = VisitRequest.fromJson(const {
        'id': 'visit-1',
        'status': 'requested',
        'estimated_price_cents': 2500,
      });

      expect(visit.requestedActs, isEmpty);
      expect(visit.address, isEmpty);
      expect(visit.addressLine, ',  ');
    });
  });
}
