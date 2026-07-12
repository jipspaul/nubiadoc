// Contrat POST /v1/cabinet/members — vérifie que first_name/last_name (requis
// côté API, cf. PostCabinetMemberBody) sont bien présents dans le payload
// envoyé par MembersApi.invite, et que la réponse 201 est bien parsée.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/members/members_api.dart';
import 'package:nubia_domain/src/entities/member.dart';

class _FakeApiClient implements ApiClient {
  @override
  Dio dio;
  _FakeApiClient(this.dio);
}

void main() {
  group('MembersApi.invite — contrat payload POST /v1/cabinet/members', () {
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
                data: {
                  'user_id': 'u1',
                  'cabinet_id': 'c1',
                  'first_name': captured['first_name'],
                  'last_name': captured['last_name'],
                  'email': captured['email'],
                  'role': captured['role'],
                  'is_active': true,
                  'joined_at': '2026-01-01T00:00:00Z',
                },
                statusCode: 201,
                requestOptions: options,
              ),
            );
          },
        ),
      );
    });

    test('inclut first_name et last_name dans le corps (sinon 422 API)',
        () async {
      final api = MembersApi(_FakeApiClient(dio));
      final result = await api.invite(
        'nouveau@cabinet.fr',
        MemberRole.secretary,
        'Camille',
        'Durand',
      );

      expect(captured['first_name'], 'Camille',
          reason: 'first_name manquant → API 422 missing field first_name');
      expect(captured['last_name'], 'Durand',
          reason: 'last_name manquant → API 422 missing field last_name');
      expect(captured['email'], 'nouveau@cabinet.fr');
      expect(captured['role'], 'secretary');
      expect(result.email, 'nouveau@cabinet.fr');
    });
  });
}
