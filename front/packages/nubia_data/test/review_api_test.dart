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

    // Pin #6866 (QA-20260912-2) : même symptôme que #7076, repris avec
    // l'enveloppe paginée réelle ({"data": [...], "page": {...}}) sur le
    // provider f0000000-0000-0000-0000-0000000000f1 du repro QA — déjà
    // corrigé ci-dessus, ce test fixe juste la forme exacte du repro.
    test('lit response.data[\'data\'] avec l\'enveloppe paginée {data,page}',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/providers/f0000000-0000-0000-0000-0000000000f1/reviews',
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'cc89a84a-826f-457a-9816-798ac6a017b7',
              'provider_id': 'f0000000-0000-0000-0000-0000000000f1',
              'rating': 4,
              'comment': 'Avis QA R54 — controle de moderation.',
              'author_name': 'Marc D.',
              'created_at': '2026-09-08T18:09:24.336372+00:00',
              'status': 'published',
            },
          ],
          'page': {'page': 1, 'per_page': 20, 'total': 1},
        }),
      );

      final reviews = await ReviewApi(
        apiClient,
      ).getProviderReviews('f0000000-0000-0000-0000-0000000000f1');

      expect(reviews.length, 1);
      expect(reviews.single.id, 'cc89a84a-826f-457a-9816-798ac6a017b7');
    });

    test('renvoie une liste vide quand data est vide (total: 0)', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/providers/a0000000-0000-0000-0000-0000000000a1/reviews',
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': <dynamic>[],
          'page': {'page': 1, 'per_page': 20, 'total': 0},
        }),
      );

      final reviews = await ReviewApi(
        apiClient,
      ).getProviderReviews('a0000000-0000-0000-0000-0000000000a1');

      expect(reviews, isEmpty);
    });
  });

  // Régression #6908 : POST /v1/reviews répond {"review_id", "status"}
  // (api/src/reviews.rs::CreateReviewResponse), pas le DTO de lecture complet
  // (id, provider_id, appointment_id, author_name, created_at...). Décoder
  // cette réponse avec `ReviewDto.fromJson` plantait sur les champs absents :
  // un 201 effectif s'affichait comme "Erreur de décodage de la réponse.".
  group('ReviewApi.submitReview', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(
          data: data,
          statusCode: 201,
          requestOptions: RequestOptions(path: ''),
        );

    test('décode {review_id, status} sans lever', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/reviews',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'review_id': 'd3ec0b40-c442-4ca6-bbbc-8c35a0746b67',
          'status': 'pending',
        }),
      );

      final result = await ReviewApi(apiClient).submitReview(
        appointmentId: 'appt-1',
        rating: 4,
        idempotencyKey: 'key-1',
      );

      expect(result.id, 'd3ec0b40-c442-4ca6-bbbc-8c35a0746b67');
      expect(result.status, 'pending');
    });
  });
}
