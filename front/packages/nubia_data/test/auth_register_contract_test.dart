// Contrat POST /v1/auth/register — vérifie que les champs requis par l'API
// (accept_cgu, cgu_version) sont bien présents dans le payload envoyé.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/auth/auth_api.dart';

class _FakeApiClient implements ApiClient {
  @override
  Dio dio;
  _FakeApiClient(this.dio);
}

void main() {
  group('AuthApi.register — contrat payload POST /v1/auth/register', () {
    late Dio dio;
    late Map<String, dynamic> captured;

    setUp(() {
      captured = {};
      dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = Map<String, dynamic>.from(
              options.data as Map<String, dynamic>? ?? {},
            );
            handler.resolve(
              Response(
                data: {'access_token': 'tok', 'refresh_token': 'ref'},
                statusCode: 201,
                requestOptions: options,
              ),
            );
          },
        ),
      );
    });

    test('inclut accept_cgu et cgu_version dans le corps', () async {
      final api = AuthApi(_FakeApiClient(dio));
      await api.register(
        email: 'test@example.com',
        password: 'pass12345',
        acceptCgu: true,
        cguVersion: '1.0',
      );

      expect(captured['accept_cgu'], isTrue,
          reason: 'accept_cgu manquant → API 422');
      expect(captured['cgu_version'], '1.0',
          reason: 'cgu_version manquant → API 422');
      expect(captured['email'], 'test@example.com');
      expect(captured['password'], 'pass12345');
      expect(captured.containsKey('invite_token'), isFalse,
          reason: 'invite_token absent pour un signup self-service');
    });

    test('inclut invite_token quand fourni', () async {
      final api = AuthApi(_FakeApiClient(dio));
      await api.register(
        email: 'pro@example.com',
        password: 'pass12345',
        acceptCgu: true,
        cguVersion: '1.0',
        inviteToken: 'tok-abc',
      );

      expect(captured['invite_token'], 'tok-abc');
    });
  });
}
