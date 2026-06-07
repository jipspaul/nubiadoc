import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage secureStorage;
  late TokenStorage tokenStorage;

  setUp(() {
    secureStorage = MockFlutterSecureStorage();
    tokenStorage = TokenStorage(secureStorage);
  });

  group('TokenStorage', () {
    test('getAccessToken returns stored value', () async {
      when(() => secureStorage.read(key: 'nubia_access_token'))
          .thenAnswer((_) async => 'access-123');

      final result = await tokenStorage.getAccessToken();

      expect(result, 'access-123');
    });

    test('getRefreshToken returns stored value', () async {
      when(() => secureStorage.read(key: 'nubia_refresh_token'))
          .thenAnswer((_) async => 'refresh-456');

      final result = await tokenStorage.getRefreshToken();

      expect(result, 'refresh-456');
    });

    test('saveTokens writes both tokens', () async {
      when(() => secureStorage.write(
            key: 'nubia_access_token',
            value: 'access-abc',
          )).thenAnswer((_) async {});
      when(() => secureStorage.write(
            key: 'nubia_refresh_token',
            value: 'refresh-xyz',
          )).thenAnswer((_) async {});

      await tokenStorage.saveTokens(access: 'access-abc', refresh: 'refresh-xyz');

      verify(() => secureStorage.write(
            key: 'nubia_access_token',
            value: 'access-abc',
          )).called(1);
      verify(() => secureStorage.write(
            key: 'nubia_refresh_token',
            value: 'refresh-xyz',
          )).called(1);
    });

    test('clearTokens deletes both keys', () async {
      when(() => secureStorage.delete(key: 'nubia_access_token'))
          .thenAnswer((_) async {});
      when(() => secureStorage.delete(key: 'nubia_refresh_token'))
          .thenAnswer((_) async {});

      await tokenStorage.clearTokens();

      verify(() => secureStorage.delete(key: 'nubia_access_token')).called(1);
      verify(() => secureStorage.delete(key: 'nubia_refresh_token')).called(1);
    });

    test('getAccessToken returns null when not set', () async {
      when(() => secureStorage.read(key: 'nubia_access_token'))
          .thenAnswer((_) async => null);

      final result = await tokenStorage.getAccessToken();

      expect(result, isNull);
    });
  });
}
