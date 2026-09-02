import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_data/src/repositories/pharmacy_session_repository_impl.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockPharmacySessionApi extends Mock implements PharmacySessionApi {}

class MockDio extends Mock implements Dio {}

class FakeTokenStorage implements TokenStorage {
  String? access;
  String? refresh;
  String? fcm;
  FakeTokenStorage({this.access, this.refresh});

  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getRefreshToken() async => refresh;
  @override
  Future<String?> getFcmToken() async => fcm;
  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> saveFcmToken(String token) async => fcm = token;
  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }

  @override
  Future<void> clearFcmToken() async => fcm = null;
}

DioException _dioError(int status) => DioException(
      requestOptions: RequestOptions(path: '/auth/select-pharmacy-context'),
      response: Response(
        requestOptions: RequestOptions(path: '/auth/select-pharmacy-context'),
        statusCode: status,
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  group('DTOs', () {
    test('PharmacyMembershipDto.fromJson parse pharmacy_id et role', () {
      final dto = PharmacyMembershipDto.fromJson(const {
        'pharmacy_id': 'f1',
        'role': 'pharmacist',
      });
      expect(dto.toDomain(),
          const PharmacyMembership(pharmacyId: 'f1', role: 'pharmacist'));
    });

    // #6170 : le nom de la pharmacie sélectionnée doit atteindre le shell pro.
    test('PharmacyMembershipDto.fromJson parse pharmacy_name', () {
      final dto = PharmacyMembershipDto.fromJson(const {
        'pharmacy_id': 'f1',
        'role': 'pharmacist',
        'pharmacy_name': 'Pharmacie du Rhône',
      });
      expect(
        dto.toDomain(),
        const PharmacyMembership(
          pharmacyId: 'f1',
          role: 'pharmacist',
          name: 'Pharmacie du Rhône',
        ),
      );
    });

    test('SelectPharmacyContextDto.fromJson parse token + context', () {
      final dto = SelectPharmacyContextDto.fromJson(const {
        'access_token': 'jwt-pharma',
        'token_type': 'Bearer',
        'expires_in': 900,
        'context': {
          'pharmacy_id': 'f1',
          'role': 'admin',
          'pharmacy_name': 'Pharmacie du Rhône',
        },
      });
      expect(dto.accessToken, 'jwt-pharma');
      expect(
        dto.toDomain(),
        const PharmacyContext(
          pharmacyId: 'f1',
          role: 'admin',
          name: 'Pharmacie du Rhône',
        ),
      );
    });

    test('SelectPharmacyContextDto défensif sur payload incomplet', () {
      final dto = SelectPharmacyContextDto.fromJson(const {});
      expect(dto.accessToken, isEmpty);
      expect(dto.pharmacyId, isEmpty);
    });
  });

  group('PharmacySessionRepositoryImpl.selectContext', () {
    late MockPharmacySessionApi api;
    late FakeTokenStorage storage;
    late PharmacySessionRepositoryImpl repo;

    setUp(() {
      api = MockPharmacySessionApi();
      storage = FakeTokenStorage(access: 'jwt-pro-login', refresh: 'refresh-1');
      repo = PharmacySessionRepositoryImpl(api, storage);
    });

    test('succès → token pharma persisté, refresh token conservé', () async {
      when(() => api.selectContext('f1')).thenAnswer(
        (_) async => const SelectPharmacyContextDto(
          accessToken: 'jwt-pharma',
          pharmacyId: 'f1',
          role: 'pharmacist',
        ),
      );

      final result = await repo.selectContext('f1');

      expect(result.isRight(), isTrue);
      expect(storage.access, 'jwt-pharma');
      expect(storage.refresh, 'refresh-1');
    });

    test('403 → ServerFailure code no_membership', () async {
      when(() => api.selectContext('f1')).thenThrow(_dioError(403));

      final result = await repo.selectContext('f1');

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect((failure as ServerFailure).code, 'no_membership');
        },
        (_) => fail('devrait échouer'),
      );
      expect(storage.access, 'jwt-pro-login');
    });

    test('404 → NotFoundFailure (anti-énumération côté back)', () async {
      when(() => api.selectContext('inconnue')).thenThrow(_dioError(404));

      final result = await repo.selectContext('inconnue');

      expect(result.fold((f) => f, (_) => null), isA<NotFoundFailure>());
    });
  });

  group('PharmacySessionRepositoryImpl.reselectContext (hook post-refresh)',
      () {
    late MockPharmacySessionApi api;
    late FakeTokenStorage storage;
    late PharmacySessionRepositoryImpl repo;
    late MockDio plainDio;

    setUp(() {
      api = MockPharmacySessionApi();
      storage = FakeTokenStorage(access: 'jwt-pro-neuf', refresh: 'refresh-2');
      repo = PharmacySessionRepositoryImpl(api, storage);
      plainDio = MockDio();
    });

    test('no-op tant qu\'aucun contexte n\'a été sélectionné', () async {
      await repo.reselectContext(plainDio);

      verifyZeroInteractions(plainDio);
      expect(storage.access, 'jwt-pro-neuf');
    });

    test('re-scope le token via le Dio nu après une sélection', () async {
      when(() => api.selectContext('f1')).thenAnswer(
        (_) async => const SelectPharmacyContextDto(
          accessToken: 'jwt-pharma-1',
          pharmacyId: 'f1',
          role: 'pharmacist',
        ),
      );
      await repo.selectContext('f1');

      when(() => plainDio.post<Map<String, dynamic>>(
            '/auth/select-pharmacy-context',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/auth/select-pharmacy-context'),
          statusCode: 200,
          data: const {
            'access_token': 'jwt-pharma-2',
            'context': {'pharmacy_id': 'f1', 'role': 'pharmacist'},
          },
        ),
      );

      await repo.reselectContext(plainDio);

      expect(storage.access, 'jwt-pharma-2');
      expect(storage.refresh, 'refresh-2');
      final captured = verify(() => plainDio.post<Map<String, dynamic>>(
            '/auth/select-pharmacy-context',
            data: captureAny(named: 'data'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured.first, {'pharmacy_id': 'f1'});
      expect(
        (captured.last as Options).headers?['Authorization'],
        'Bearer jwt-pharma-1',
      );
    });
  });
}
