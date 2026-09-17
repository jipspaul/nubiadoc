import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/waiting_room/waiting_room_api.dart';
import 'package:nubia_data/src/repositories/waiting_room_repository_impl.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // #7217 : POST /cabinet/waiting-room/call-next répond 200 avec
  // `{"called": false}` quand le back refuse l'appel (file vide côté
  // praticien, ou secrétaire sans secretariat_id actif — api/src/scheduling.rs:367).
  // Avant ce fix, `WaitingRoomEntryDto.fromJson` (défensif) parsait ce refus
  // comme une entrée vide et le repository le remontait comme un succès :
  // le CTA « Appeler » redevenait un no-op muet.
  group('WaitingRoomApi.callNext', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    test('called:false renvoie null plutôt qu\'une entrée vide', () async {
      when(() => dio.post<Map<String, dynamic>>(
            '/cabinet/waiting-room/call-next',
          )).thenAnswer((_) async => Response(
            data: const {'called': false},
            requestOptions: RequestOptions(path: ''),
          ));

      final dto = await WaitingRoomApi(apiClient).callNext();

      expect(dto, isNull);
    });

    test('called:true renvoie l\'entrée appelée', () async {
      when(() => dio.post<Map<String, dynamic>>(
            '/cabinet/waiting-room/call-next',
          )).thenAnswer((_) async => Response(
            data: const {
              'called': true,
              'appointment_id': 'appt-1',
              'patient_display_name': 'Marie Dupont',
            },
            requestOptions: RequestOptions(path: ''),
          ));

      final dto = await WaitingRoomApi(apiClient).callNext();

      expect(dto, isNotNull);
      expect(dto!.id, 'appt-1');
    });
  });

  group('WaitingRoomRepositoryImpl.callNext', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    test('called:false remonte un Failure, jamais un succès muet', () async {
      when(() => dio.post<Map<String, dynamic>>(
            '/cabinet/waiting-room/call-next',
          )).thenAnswer((_) async => Response(
            data: const {'called': false},
            requestOptions: RequestOptions(path: ''),
          ));

      final result =
          await WaitingRoomRepositoryImpl(WaitingRoomApi(apiClient)).callNext();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<NotFoundFailure>()),
        (_) => fail('called:false ne doit jamais remonter un succès'),
      );
    });
  });
}
