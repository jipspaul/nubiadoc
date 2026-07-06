import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/src/error/failure.dart';

import 'package:nubia_data/src/remote/clinical/clinical_session_api.dart';
import 'package:nubia_data/src/remote/clinical/clinical_session_dto.dart';
import 'package:nubia_data/src/repositories/clinical_session_repository_impl.dart';

class MockClinicalSessionApi extends Mock implements ClinicalSessionApi {}

DioException _dioError(int status) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
      ),
    );

const _existing = ClinicalSessionDto(
  id: 's-existing',
  appointmentId: 'appt-1',
  status: 'in_progress',
  acts: [],
);

void main() {
  late MockClinicalSessionApi api;
  late ClinicalSessionRepositoryImpl repo;

  setUp(() {
    api = MockClinicalSessionApi();
    repo = ClinicalSessionRepositoryImpl(api);
  });

  group('startSession — reprise sur 409 (#3400)', () {
    test('409 → récupère la séance in_progress du RDV et la retourne',
        () async {
      when(() => api.startSession('appt-1')).thenThrow(_dioError(409));
      when(() => api.listSessions(status: 'in_progress'))
          .thenAnswer((_) async => [_existing]);

      final result = await repo.startSession('appt-1');

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('attendu Right'),
        (session) {
          expect(session.id, 's-existing');
          expect(session.appointmentId, 'appt-1');
        },
      );
    });

    test('409 sans séance correspondante → ServerFailure 409', () async {
      when(() => api.startSession('appt-1')).thenThrow(_dioError(409));
      when(() => api.listSessions(status: 'in_progress'))
          .thenAnswer((_) async => const []);

      final result = await repo.startSession('appt-1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect((failure as ServerFailure).statusCode, 409);
        },
        (_) => fail('attendu Left'),
      );
    });
  });

  group('addAct — 403 explicite (#3403)', () {
    test('403 → ServerFailure « Action non autorisée. »', () async {
      when(() => api.addAct(
            consultationId: any(named: 'consultationId'),
            ccamCode: any(named: 'ccamCode'),
            label: any(named: 'label'),
            tooth: any(named: 'tooth'),
            amountCents: any(named: 'amountCents'),
            included: any(named: 'included'),
          )).thenThrow(_dioError(403));

      final result = await repo.addAct(
        consultationId: 's1',
        ccamCode: 'HBGD036',
        label: 'Détartrage',
        tooth: '11',
        amountCents: 2864,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, 'Action non autorisée.');
          expect((failure as ServerFailure).statusCode, 403);
        },
        (_) => fail('attendu Left'),
      );
    });
  });
}
