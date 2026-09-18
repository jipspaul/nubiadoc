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
      ).thenAnswer((_) async => _fakeResponse({'estimated_price_cents': 4000}));

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

    // Payload QA #6961 / #6861 : 3 lignes sur 50 avec `address` non-objet
    // (`[]`, `"pas un objet"`, `null`) + 1 avec `address: true`, servies en
    // 200 par GET /v1/account/visit-requests.
    List<Map<String, dynamic>> qaPayload() => [
          for (var i = 0; i < 47; i++)
            {
              'id': 'ok-$i',
              'status': 'done',
              'requested_acts': ['pansement'],
              'address': {
                'city': 'Lyon',
                'line1': '12 rue de la Republique',
                'postal_code': '69002',
              },
              'estimated_price_cents': 2000,
            },
          {
            'id': '28850f90-1240-4ef6-bcd8-99db246d7c35',
            'status': 'cancelled',
            'requested_acts': ['pansement'],
            'address': <dynamic>[],
            'estimated_price_cents': 2000,
          },
          {
            'id': '3d079852-ee48-446a-bdc9-8669cb634a02',
            'status': 'cancelled',
            'requested_acts': ['pansement'],
            'address': 'pas un objet',
            'estimated_price_cents': 2000,
          },
          {
            'id': 'f2c8db2f-1203-452c-8829-d2c62828fbcd',
            'status': 'cancelled',
            'requested_acts': ['pansement'],
            'address': null,
            'estimated_price_cents': 2000,
          },
          {
            'id': 'bool-address',
            'status': 'cancelled',
            'requested_acts': ['pansement'],
            'address': true,
            'estimated_price_cents': 2000,
          },
        ];

    blocTest<HomeCareListCubit, HomeCareListState>(
      '`address` non-objet sur 4 lignes (#6961 / #6861) → Loaded avec les '
      '51 lignes, aucune écartée, jamais bloqué sur Loading',
      setUp: () {
        when(() => dio.get<List<dynamic>>('/account/visit-requests'))
            .thenAnswer((_) async => _fakeResponse<List<dynamic>>(qaPayload()));
      },
      build: () => HomeCareListCubit(apiClient),
      act: (cubit) => cubit.load(),
      expect: () => [
        const HomeCareListLoading(),
        isA<HomeCareListLoaded>()
            .having((s) => s.requests.length, 'requests.length', 51)
            .having((s) => s.skippedCount, 'skippedCount', 0)
            .having(
          (s) => s.requests
              .where((v) => v.status == 'cancelled')
              .map((v) => v.address),
          'adresses des lignes historiques',
          [isNull, const VisitAddress(line1: 'pas un objet'), isNull, isNull],
        ),
      ],
    );

    blocTest<HomeCareListCubit, HomeCareListState>(
      'ligne indécodable (élément non-objet, `id` absent) → Loaded partiel : '
      'lignes valides conservées + skippedCount (#6961)',
      setUp: () {
        when(() => dio.get<List<dynamic>>('/account/visit-requests'))
            .thenAnswer((_) async => _fakeResponse<List<dynamic>>([
                  {
                    'id': 'visit-1',
                    'status': 'done',
                    'requested_acts': ['prise_de_sang'],
                    'address': <String, dynamic>{},
                    'estimated_price_cents': 2000,
                  },
                  'pas un objet',
                  {'status': 'done', 'estimated_price_cents': 2000},
                  {
                    'id': 'visit-2',
                    'status': 'offered',
                    'requested_acts': ['pansement', 42],
                    'estimated_price_cents': 1500.0,
                  },
                ]));
      },
      build: () => HomeCareListCubit(apiClient),
      act: (cubit) => cubit.load(),
      expect: () => [
        const HomeCareListLoading(),
        isA<HomeCareListLoaded>()
            .having(
              (s) => s.requests.map((v) => v.id),
              'ids conservés',
              ['visit-1', 'visit-2'],
            )
            .having((s) => s.skippedCount, 'skippedCount', 2)
            .having(
              (s) => s.requests.last.requestedActs,
              'actes non-chaîne ignorés',
              ['pansement'],
            )
            .having(
              (s) => s.requests.last.estimatedPriceCents,
              'prix num → int',
              1500,
            ),
      ],
    );

    blocTest<HomeCareListCubit, HomeCareListState>(
      'exception hors DioException pendant le chargement → HomeCareListError '
      '(jamais un spinner infini, #6961 / #6861)',
      setUp: () {
        when(() => dio.get<List<dynamic>>('/account/visit-requests'))
            .thenThrow(TypeError());
      },
      build: () => HomeCareListCubit(apiClient),
      act: (cubit) => cubit.load(),
      expect: () => [
        const HomeCareListLoading(),
        const HomeCareListError('Réponse inattendue du serveur.'),
      ],
    );
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
      when(() =>
              dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
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
      when(() =>
              dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
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

    test(
        'load() avec réponse indécodable → HomeCareTrackingError, pas de '
        'spinner infini (#6961)', () async {
      when(() =>
              dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
          .thenAnswer((_) async => _fakeResponse<Map<String, dynamic>>(
              {'status': 'accepted', 'estimated_price_cents': 4000}));

      final cubit = HomeCareTrackingCubit(apiClient);
      await cubit.load('visit-1');

      expect(
        cubit.state,
        const HomeCareTrackingError('Réponse inattendue du serveur.'),
      );
    });

    test('cancel() sur 409 → HomeCareTrackingError dédié', () async {
      when(() =>
              dio.get<Map<String, dynamic>>('/account/visit-requests/visit-1'))
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
    test('adresse absente → null, pas de crash', () {
      final visit = VisitRequest.fromJson(const {
        'id': 'visit-1',
        'status': 'requested',
        'estimated_price_cents': 2500,
      });

      expect(visit.requestedActs, isEmpty);
      expect(visit.address, isNull);
      expect(visit.addressLine, '');
      expect(visit.nurseDisplayName, isNull);
    });

    test('adresse non-objet (donnée historique #7027) → null, pas de crash',
        () {
      final visit = VisitRequest.fromJson(const {
        'id': 'visit-1',
        'status': 'cancelled',
        'estimated_price_cents': 2500,
        'address': 42,
      });

      expect(visit.address, isNull);
      expect(visit.addressLine, '');
    });

    test('adresse complète → line1, code postal + ville (#7121)', () {
      final visit = VisitRequest.fromJson(const {
        'id': 'visit-1',
        'status': 'requested',
        'estimated_price_cents': 2500,
        'address': {
          'line1': '1 rue de Rivoli',
          'postal_code': '75001',
          'city': 'Paris',
        },
      });

      expect(
        visit.address,
        const VisitAddress(
          line1: '1 rue de Rivoli',
          postalCode: '75001',
          city: 'Paris',
        ),
      );
      expect(visit.addressLine, '1 rue de Rivoli, 75001 Paris');
    });

    test('nurse_display_name présent → exposé (#6506)', () {
      final visit = VisitRequest.fromJson(const {
        'id': 'visit-1',
        'status': 'accepted',
        'estimated_price_cents': 2500,
        'nurse_display_name': 'Camille D.',
      });

      expect(visit.nurseDisplayName, 'Camille D.');
    });

    test('`id` absent ou non-chaîne → FormatException (ligne inexploitable)',
        () {
      expect(
        () => VisitRequest.fromJson(const {'status': 'done'}),
        throwsFormatException,
      );
      expect(
        () => VisitRequest.fromJson(const {'id': 12, 'status': 'done'}),
        throwsFormatException,
      );
    });

    test(
        'champs secondaires mal typés → valeurs par défaut, jamais de '
        'TypeError', () {
      final visit = VisitRequest.fromJson(const {
        'id': 'visit-1',
        'status': 7,
        'requested_acts': 'pansement',
        'estimated_price_cents': '2500',
        'nurse_display_name': <String, dynamic>{},
      });

      expect(visit.status, 'requested');
      expect(visit.requestedActs, isEmpty);
      expect(visit.estimatedPriceCents, 0);
      expect(visit.nurseDisplayName, isNull);
    });
  });

  // Les 3 formes observées par le QA (#6961 / #6861) + les scalaires.
  group('VisitAddress.tryParse', () {
    test('objet → champs décodés', () {
      expect(
        VisitAddress.tryParse(const {
          'city': 'Lyon',
          'line1': '12 rue de la Republique',
          'postal_code': '69002',
        }),
        const VisitAddress(
          line1: '12 rue de la Republique',
          postalCode: '69002',
          city: 'Lyon',
        ),
      );
    });

    test('objet aux champs mal typés → champs ignorés, nombre toléré', () {
      expect(
        VisitAddress.tryParse(const {
          'line1': <dynamic>[],
          'postal_code': 69002,
          'city': '  Lyon ',
        }),
        const VisitAddress(postalCode: '69002', city: 'Lyon'),
      );
      expect(VisitAddress.tryParse(const <String, dynamic>{}), isNull);
      expect(VisitAddress.tryParse(const {'line1': '   '}), isNull);
    });

    test('chaîne → adresse libre (line1), vide → null', () {
      expect(
        VisitAddress.tryParse('pas un objet'),
        const VisitAddress(line1: 'pas un objet'),
      );
      expect(VisitAddress.tryParse('pas un objet')!.line, 'pas un objet');
      expect(VisitAddress.tryParse('   '), isNull);
    });

    test('null / liste / booléen / nombre → null, jamais de TypeError', () {
      expect(VisitAddress.tryParse(null), isNull);
      expect(VisitAddress.tryParse(const <dynamic>[]), isNull);
      expect(VisitAddress.tryParse(const ['12 rue', 'Lyon']), isNull);
      expect(VisitAddress.tryParse(true), isNull);
      expect(VisitAddress.tryParse(42), isNull);
    });
  });
}
