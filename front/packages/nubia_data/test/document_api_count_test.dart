import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/documents/document_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // #8279 : le compteur de l'accueil (« 737 fichiers ») paginait le coffre-
  // fort entier (37 requêtes) pour en prendre la longueur. count() doit se
  // contenter d'une seule page bornée et lire `page.total`.
  group('DocumentApi.count', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    test('demande une seule page bornée et renvoie page.total', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/documents',
          queryParameters: <String, dynamic>{'limit': 1},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'doc1',
              'category': 'radio',
              'filename': 'radio.pdf',
              'mime_type': 'application/pdf',
              'size_bytes': 100,
              'created_at': '2026-09-24T09:45:54Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 1, 'total': 737},
        }),
      );

      final total = await DocumentApi(apiClient).count();

      expect(total, 737);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/documents',
          queryParameters: <String, dynamic>{'limit': 1},
        ),
      ).called(1);
    });

    test('propage patientAccount en paramètre de requête', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/documents',
          queryParameters: <String, dynamic>{
            'patient_account': 'dependent-1',
            'limit': 1,
          },
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': <dynamic>[],
          'page': {'next_cursor': null, 'limit': 1, 'total': 0},
        }),
      );

      final total =
          await DocumentApi(apiClient).count(patientAccount: 'dependent-1');

      expect(total, 0);
    });
  });
}
