import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';
import 'package:nubia_patient/data/remote/auth/auth_api.dart';
import 'package:nubia_patient/data/remote/auth/auth_dto.dart';
import 'package:nubia_patient/data/repositories/auth_repository_impl.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

class MockAuthApi extends Mock implements AuthApi {}

class MockTokenStorage extends Mock implements TokenStorage {}

const _accountDto = PatientAccountDto(
  id: 'u1',
  firstName: 'Alice',
  lastName: 'Martin',
  email: 'alice@example.com',
);

const _tokens = TokenResponseDto(
  accessToken: 'access123',
  refreshToken: 'refresh456',
);

const _authResponse = AuthResponseDto(
  tokens: _tokens,
  account: _accountDto,
);

DioException _dioError(int statusCode) => DioException(
      requestOptions: RequestOptions(path: '/'),
      response: Response(
        requestOptions: RequestOptions(path: '/'),
        statusCode: statusCode,
      ),
      type: DioExceptionType.badResponse,
    );

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );

void main() {
  late MockAuthApi api;
  late MockTokenStorage tokenStorage;
  late AuthRepositoryImpl repository;

  setUp(() {
    api = MockAuthApi();
    tokenStorage = MockTokenStorage();
    repository = AuthRepositoryImpl(api, tokenStorage);
    when(() => tokenStorage.saveTokens(
          access: any(named: 'access'),
          refresh: any(named: 'refresh'),
        )).thenAnswer((_) async {});
    when(() => tokenStorage.clearTokens()).thenAnswer((_) async {});
  });

  group('login', () {
    test('success: saves tokens and returns PatientAccount', () async {
      when(() => api.login(email: 'alice@example.com', password: 'secret'))
          .thenAnswer((_) async => _authResponse);

      final result = await repository.login(
        email: 'alice@example.com',
        password: 'secret',
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (account) {
          expect(account.id, 'u1');
          expect(account.email, 'alice@example.com');
        },
      );
      verify(() => tokenStorage.saveTokens(
            access: 'access123',
            refresh: 'refresh456',
          )).called(1);
    });

    test('network error returns NetworkFailure', () async {
      when(() => api.login(
                email: any(named: 'email'),
                password: any(named: 'password'),
              ))
          .thenThrow(_networkError());

      final result = await repository.login(
        email: 'alice@example.com',
        password: 'secret',
      );

      expect(result, const Left<Failure, PatientAccount>(NetworkFailure()));
    });

    test('401 returns UnauthorizedFailure', () async {
      when(() => api.login(
                email: any(named: 'email'),
                password: any(named: 'password'),
              ))
          .thenThrow(_dioError(401));

      final result = await repository.login(
        email: 'alice@example.com',
        password: 'wrong',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<UnauthorizedFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });

  group('register', () {
    test('success: saves tokens and returns PatientAccount', () async {
      when(() => api.register(
                email: 'alice@example.com',
                password: 'secret',
                inviteToken: 'tok',
              ))
          .thenAnswer((_) async => _authResponse);

      final result = await repository.register(
        email: 'alice@example.com',
        password: 'secret',
        inviteToken: 'tok',
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (account) => expect(account.email, 'alice@example.com'),
      );
      verify(() => tokenStorage.saveTokens(
            access: 'access123',
            refresh: 'refresh456',
          )).called(1);
    });
  });

  group('refreshToken', () {
    test('success: stores new tokens', () async {
      when(() => tokenStorage.getRefreshToken())
          .thenAnswer((_) async => 'refresh456');
      when(() => api.refresh(refreshToken: 'refresh456'))
          .thenAnswer((_) async => const TokenResponseDto(
                accessToken: 'newAccess',
                refreshToken: 'newRefresh',
              ));

      final result = await repository.refreshToken();

      expect(result, const Right<Failure, void>(null));
      verify(() => tokenStorage.saveTokens(
            access: 'newAccess',
            refresh: 'newRefresh',
          )).called(1);
    });

    test('no stored refresh token returns UnauthorizedFailure', () async {
      when(() => tokenStorage.getRefreshToken())
          .thenAnswer((_) async => null);

      final result = await repository.refreshToken();

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<UnauthorizedFailure>()),
        (_) => fail('expected failure'),
      );
    });

    test('network error returns NetworkFailure', () async {
      when(() => tokenStorage.getRefreshToken())
          .thenAnswer((_) async => 'refresh456');
      when(() => api.refresh(refreshToken: any(named: 'refreshToken')))
          .thenThrow(_networkError());

      final result = await repository.refreshToken();

      expect(result, const Left<Failure, void>(NetworkFailure()));
    });
  });
}
