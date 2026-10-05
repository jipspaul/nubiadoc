import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_api.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #6914 : le CTA « Générer le devis de la phase N » du plan de
  // traitement ne produisait rien — entre autres parce que `create` postait
  // un corps (`total_cents`/`patient_share_cents`/`status`) rejeté par le
  // contrat back `CreateCabinetQuoteBody` (`#[serde(deny_unknown_fields)]`,
  // seuls `patient_id`/`items`/`deposit_pct` acceptés) et traitait la
  // réponse `{quote_id, total_amount_cents}` comme un devis complet.
  group('CabinetQuotesApi.create', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    final quote = CabinetQuote(
      id: '',
      quoteRef: '',
      cabinetId: '',
      patientId: 'pat-1',
      patientName: '',
      totalCents: 15000,
      patientShareCents: 15000,
      status: CabinetQuoteStatus.draft,
      createdAt: DateTime.now(),
      items: const [
        QuoteLineItem(
          id: 'act-1',
          label: 'Couronne céramique',
          ccamCode: 'HBLD038',
          toothLabel: '26',
          totalCents: 15000,
          amoShareCents: 0,
          amcShareCents: 0,
          patientShareCents: 15000,
        ),
      ],
    );

    test('poste patient_id/items au contrat back, pas total_cents/status',
        () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/cabinet/quotes',
          data: {
            'patient_id': 'pat-1',
            'items': [
              {
                'label': 'Couronne céramique',
                'amount_cents': 15000,
                'ccam_code': 'HBLD038',
                'tooth': '26',
              },
            ],
          },
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'quote_id': 'q-new',
          'total_amount_cents': 150,
        }),
      );
      when(() => dio.get<Map<String, dynamic>>('/cabinet/quotes/q-new'))
          .thenAnswer(
        (_) async => fakeResponse({
          'id': 'q-new',
          'quote_ref': 'DEV-0099',
          'patient_id': 'pat-1',
          'patient_name': 'Marc Dubois',
          'total_amount': 15000,
          'patient_share_cents': 15000,
          'status': 'draft',
          'created_at': '2026-09-13T09:00:00Z',
        }),
      );

      final dto = await CabinetQuotesApi(apiClient).create(quote);

      expect(dto.id, 'q-new');
      expect(dto.quoteRef, 'DEV-0099');
      expect(dto.status, 'draft');
    });
  });
}
