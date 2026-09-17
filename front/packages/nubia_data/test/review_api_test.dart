import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/reviews/review_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #7076 : GET /providers/:id/reviews renvoie l'enveloppe
  // {"data": [...]} (comme BillingApi.getQuotes) et jamais un tableau nu ;
  // les items publics n'ont pas de `appointment_id` (surface publique, cf.
  // api/src/reviews.rs). Le client attendait un tableau nu et un
  // `appointment_id` requis : chaque appel échouait et l'écran patient
  // affichait "Erreur lors de la récupération des avis." en boucle.
  group('ReviewApi.getProviderReviews', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    test('lit response.data[\'data\'] sans appointment_id', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/providers/prov-1/reviews',
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'rev-1',
              'provider_id': 'prov-1',
              'rating': 4,
              'comment': 'QA-R64 avis de test.',
              'author_name': 'Marc D.',
              'created_at': '2026-09-12T19:34:12.279901+00:00',
              'status': 'published',
            },
          ],
        }),
      );

      final reviews = await ReviewApi(apiClient).getProviderReviews('prov-1');

      expect(reviews.length, 1);
      expect(reviews.single.id, 'rev-1');
      expect(reviews.single.appointmentId, isNull);
      expect(reviews.single.rating, 4);
    });
  });
}
