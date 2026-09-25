// Contrats POST /v1/cabinet/invite-links et POST /v1/cabinet/provider/
// {signature,stamp} (#7148/#7147) : vérifie le payload envoyé et le parsing
// de la réponse, même pattern que `members_api_contract_test.dart`.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_invite_links/cabinet_invite_links_api.dart';
import 'package:nubia_data/src/remote/provider_stamp/provider_stamp_api.dart';

class _FakeApiClient implements ApiClient {
  @override
  Dio dio;
  _FakeApiClient(this.dio);
}

void main() {
  group('CabinetInviteLinksApi.create — contrat POST /v1/cabinet/invite-links',
      () {
    test('envoie le rôle et parse la réponse 201', () async {
      Map<String, dynamic> captured = {};
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = Map<String, dynamic>.from(
              options.data as Map<String, dynamic>? ?? {},
            );
            handler.resolve(
              Response(
                data: {
                  'id': 'l1',
                  'role': captured['role'],
                  'token': 'tok-1',
                  'url':
                      'https://app.nubia.invalid/register?invite_link_token=tok-1',
                  'max_uses': 20,
                  'expires_at': '2026-02-01T00:00:00Z',
                },
                statusCode: 201,
                requestOptions: options,
              ),
            );
          },
        ),
      );

      final api = CabinetInviteLinksApi(_FakeApiClient(dio));
      final dto = await api.create('secretary');

      expect(captured['role'], 'secretary');
      expect(dto.token, 'tok-1');
      expect(dto.maxUses, 20);
      expect(
        dto.toDomain().url,
        'https://app.nubia.invalid/register?invite_link_token=tok-1',
      );
    });
  });

  group(
      'ProviderStampApi — contrat POST /v1/cabinet/provider/{signature,stamp}',
      () {
    late Dio dio;
    late FormData? captured;

    setUp(() {
      captured = null;
      dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options.data as FormData?;
            handler.resolve(
              Response(
                data: {'document_id': 'doc-1', 'size_bytes': 3},
                statusCode: 201,
                requestOptions: options,
              ),
            );
          },
        ),
      );
    });

    test('uploadSignature envoie le fichier sous le champ "file"', () async {
      final api = ProviderStampApi(_FakeApiClient(dio));
      final documentId = await api.uploadSignature(
        bytes: [1, 2, 3],
        filename: 'signature.jpg',
        mimeType: 'image/jpeg',
      );

      expect(captured!.files, hasLength(1));
      expect(captured!.files.first.key, 'file');
      expect(captured!.files.first.value.filename, 'signature.jpg');
      expect(documentId, 'doc-1');
    });

    test('uploadStamp envoie le fichier sous le champ "file"', () async {
      final api = ProviderStampApi(_FakeApiClient(dio));
      final documentId = await api.uploadStamp(
        bytes: [4, 5, 6],
        filename: 'tampon.jpg',
        mimeType: 'image/jpeg',
      );

      expect(captured!.files, hasLength(1));
      expect(captured!.files.first.key, 'file');
      expect(documentId, 'doc-1');
    });
  });
}
