import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/prescriptions/prescription_api.dart';
import 'package:nubia_domain/src/entities/prescription.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression : les routes de mutation d'ordonnance renvoient des réponses
  // PARTIELLES (create → {prescription_id}, sign → {signed_at, document_id},
  // send → un OrderDto) — pas l'ordonnance complète. Parser ça comme un
  // PrescriptionDto jetait un TypeError (`json['id']` null → cast String) alors
  // que la mutation avait réussi côté serveur : l'utilisateur voyait
  // « ça ne fonctionne pas ». Le fix re-GET l'objet complet via l'endpoint
  // canonique. Ces tests verrouillent ce comportement.
  group('PrescriptionApi (re-fetch après mutation partielle)', () {
    late MockApiClient apiClient;
    late MockDio dio;
    late PrescriptionApi api;

    const id = '94d64bae-c3b1-462b-a750-8b6880961b78';

    Response<Map<String, dynamic>> resp(Map<String, dynamic> data) => Response(
          data: data,
          requestOptions: RequestOptions(path: ''),
        );

    Map<String, dynamic> fullPrescription(String status) => {
          'id': id,
          'patient_id': 'd0000000-0000-0000-0000-0000000000d1',
          'status': status,
          'created_at': '2026-08-09T13:12:10.252657+00:00',
          'items': [
            {
              'id': 'item-1',
              'label': 'Amoxicilline 500mg',
              'form': 'comprimé',
              'posology': '1 cp x3/j',
              'duration': '7 jours',
              'quantity': '21',
            },
          ],
        };

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
      api = PrescriptionApi(apiClient);
    });

    test(
        'createPrescription: POST ne renvoie que {prescription_id} → re-GET '
        'l\'objet complet (pas de crash de parsing)', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/cabinet/prescriptions',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => resp({'prescription_id': id}));
      when(
        () => dio.get<Map<String, dynamic>>('/cabinet/prescriptions/$id'),
      ).thenAnswer((_) async => resp(fullPrescription('draft')));

      final dto = await api.createPrescription(
        patientId: 'd0000000-0000-0000-0000-0000000000d1',
        items: const [
          PrescriptionItem(
            label: 'Amoxicilline 500mg',
            form: 'comprimé',
            posology: '1 cp x3/j',
            duration: '7 jours',
            quantity: '21',
          ),
        ],
      );

      expect(dto.id, id);
      expect(dto.status, 'draft');
      expect(dto.items, hasLength(1));
      // le re-fetch a bien eu lieu
      verify(() => dio.get<Map<String, dynamic>>('/cabinet/prescriptions/$id'))
          .called(1);
    });

    test(
        'signPrescription: POST ne renvoie que {signed_at, document_id} → '
        're-GET l\'objet complet (statut signed)', () async {
      when(
        () => dio.post<Map<String, dynamic>>('/cabinet/prescriptions/$id/sign'),
      ).thenAnswer((_) async => resp({
            'signed_at': '2026-08-09T13:12:30.545518+00:00',
            'document_id': 'fa98c264-0a02-4292-9365-7df1ded39d78',
          }));
      when(
        () => dio.get<Map<String, dynamic>>('/cabinet/prescriptions/$id'),
      ).thenAnswer((_) async => resp(fullPrescription('signed')));

      final dto = await api.signPrescription(id);

      expect(dto.id, id);
      expect(dto.status, 'signed');
      verify(() => dio.get<Map<String, dynamic>>('/cabinet/prescriptions/$id'))
          .called(1);
    });
  });
}
