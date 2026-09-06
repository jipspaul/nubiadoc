import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/cabinet_dashboard/cabinet_dashboard_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #3861 : GET /cabinet/appointments?status=requested (sans
  // `date`) comptait TOUS les RDV requested toutes dates confondues — RDV
  // périmés de 2021/2025 inclus (105 au lieu de 11 réellement actionnables
  // aujourd'hui). L'appel "confirmations en attente" doit être borné au
  // même jour que l'appel "RDV du jour" (todayIso).
  group('CabinetDashboardApi.getSummary', () {
    late MockApiClient apiClient;
    late MockDio dio;

    Response<Map<String, dynamic>> fakeResponse(List<dynamic> data) => Response(
          data: {'data': data},
          requestOptions: RequestOptions(path: ''),
        );

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
      // Stub par défaut de l'appel hebdomadaire (#6037) : les tests qui
      // n'exercent pas les compteurs `weekly*` n'ont pas à le redéclarer,
      // sinon MockDio renvoie null et `getSummary()` casse.
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/stats/activity',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => fakeResponse(const []));
    });

    test('la requête "requested" inclut le paramètre date (borné au jour)',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/appointments',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((invocation) async {
        final params = invocation.namedArguments[#queryParameters]
            as Map<String, dynamic>?;
        if (params?['status'] == 'requested') {
          // Périmés (2021/2025) exclus par la borne date : seuls les
          // RDV du jour "actionnables" doivent apparaître ici.
          expect(
            params?['date'],
            isNotNull,
            reason: 'la requête status=requested doit être bornée par date, '
                'sinon elle compte tous les RDV requested toutes dates '
                'confondues (105 au lieu de 11 réels)',
          );
          return fakeResponse(List.filled(11, <String, dynamic>{}));
        }
        if (params?['status'] == 'no_show') {
          return fakeResponse(List.filled(2, <String, dynamic>{}));
        }
        // Appel "RDV du jour" (results[0]).
        return fakeResponse(List.filled(43, <String, dynamic>{}));
      });
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/waiting-room',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse(const []));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse(const []));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/stats/activity',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => fakeResponse([
          {'act_count': 5, 'total_amount_cents': 12000},
          {'act_count': 3, 'total_amount_cents': 8000},
        ]),
      );

      final summary = await CabinetDashboardApi(apiClient).getSummary();

      expect(
        summary.pendingConfirmations,
        11,
        reason: 'ne doit compter que les requested du jour, pas 105 '
            'toutes dates confondues',
      );
      expect(
        summary.weeklyCompletedActs,
        8,
        reason: 'somme des act_count de /cabinet/stats/activity (lundi-vendredi)',
      );
      expect(
        summary.weeklyFeesCents,
        20000,
        reason:
            'somme des total_amount_cents de /cabinet/stats/activity (lundi-vendredi)',
      );
      expect(
        summary.weeklyNoShowCount,
        greaterThan(0),
        reason: 'no_show agrégés depuis /cabinet/appointments?status=no_show '
            'sur les jours ouvrés déjà écoulés de la semaine',
      );
    });

    test(
        'associe le patient suivant depuis la salle d\'attente + la durée '
        'du RDV du jour (#5045)', () async {
      final arrivedAt = DateTime.now().subtract(const Duration(minutes: 12));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/appointments',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((invocation) async {
        final params = invocation.namedArguments[#queryParameters]
            as Map<String, dynamic>?;
        if (params?['status'] == 'requested') {
          return fakeResponse(const []);
        }
        return fakeResponse([
          {
            'id': 'appt-1',
            'patient_id': 'pat-1',
            'patient_name': 'Camille Moreau',
            'practitioner_id': 'prac-1',
            'practitioner_name': 'Dr. Rousseau',
            'starts_at': '2026-08-26T14:30:00.000Z',
            'duration_minutes': 30,
            'motif': 'Pose de couronne',
            'status': 'confirmed',
          },
        ]);
      });
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/waiting-room',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse([
            {
              'appointment_id': 'appt-1',
              'patient_id': 'pat-1',
              'patient_name': 'Camille Moreau',
              'motif': 'Pose de couronne',
              'starts_at': '2026-08-26T14:30:00.000Z',
              'checkin_at': arrivedAt.toIso8601String(),
            },
          ]));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse(const []));

      final summary = await CabinetDashboardApi(apiClient).getSummary();

      expect(summary.nextPatientName, 'Camille Moreau');
      expect(summary.nextPatientReason, 'Pose de couronne');
      expect(
        summary.nextPatientDurationMinutes,
        30,
        reason: 'joint le RDV du jour correspondant pour la durée prévue',
      );
      expect(summary.nextPatientWaitingMinutes, greaterThanOrEqualTo(11));
      expect(
        summary.nextPatientAppointmentId,
        'appt-1',
        reason: '#6241 — le hero doit pouvoir démarrer CE RDV, pas un '
            'RDV générique',
      );
      expect(
        summary.nextPatientPatientId,
        'pat-1',
        reason: '#6241 — le hero doit pouvoir ouvrir la fiche de CE patient',
      );
    });

    test(
        'préfère le nom complet du RDV du jour aux initiales renvoyées par '
        'la salle d\'attente (#6576)', () async {
      final arrivedAt = DateTime.now().subtract(const Duration(minutes: 507));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/appointments',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((invocation) async {
        final params = invocation.namedArguments[#queryParameters]
            as Map<String, dynamic>?;
        if (params?['status'] == 'requested') {
          return fakeResponse(const []);
        }
        return fakeResponse([
          {
            'id': 'appt-1',
            'patient_id': 'pat-1',
            'patient_name': 'Marc Dubois',
            'practitioner_id': 'prac-1',
            'practitioner_name': 'Dr. Marin',
            'starts_at': '2026-09-05T14:11:00.000Z',
            'duration_minutes': 20,
            'motif': 'Contrôle',
            'status': 'in_progress',
          },
        ]);
      });
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/waiting-room',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse([
            {
              'appointment_id': 'appt-1',
              'patient_id': 'pat-1',
              // Reproduit le payload live de #6576 : `/cabinet/waiting-room`
              // ne renvoie que les initiales, jamais le nom complet.
              'patient_name_initials': 'MD',
              'checkin_at': arrivedAt.toIso8601String(),
            },
          ]));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse(const []));

      final summary = await CabinetDashboardApi(apiClient).getSummary();

      expect(
        summary.nextPatientName,
        'Marc Dubois',
        reason: 'le héros doit afficher le nom complet, comme la liste '
            '"Journée" alimentée par le même RDV, pas les initiales de la '
            'salle d\'attente',
      );
    });

    test('nextPatient est absent quand la salle d\'attente est vide', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/appointments',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => fakeResponse(const []));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/waiting-room',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse(const []));
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations',
          queryParameters: null,
        ),
      ).thenAnswer((_) async => fakeResponse(const []));

      final summary = await CabinetDashboardApi(apiClient).getSummary();

      expect(summary.nextPatientName, isNull);
    });
  });
}
