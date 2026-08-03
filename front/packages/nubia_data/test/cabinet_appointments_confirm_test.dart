// #4535 : un 409 sur confirm() ne doit plus être avalé comme un faux succès
// (l'appelant croyait le RDV confirmé alors qu'un vrai conflit d'état
// l'empêchait — silence total côté UI).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_api.dart';
import 'package:nubia_data/src/repositories/cabinet_appointments_repository_impl.dart';
import 'package:nubia_domain/src/error/failure.dart';

class MockCabinetAppointmentsApi extends Mock
    implements CabinetAppointmentsApi {}

void main() {
  late MockCabinetAppointmentsApi api;
  late CabinetAppointmentsRepositoryImpl repository;

  setUp(() {
    api = MockCabinetAppointmentsApi();
    repository = CabinetAppointmentsRepositoryImpl(api);
  });

  test('confirm() sur 409 renvoie une vraie erreur, pas un faux succès',
      () async {
    when(() => api.confirm(any())).thenThrow(
      DioException(
        requestOptions:
            RequestOptions(path: '/cabinet/appointments/a-1/confirm'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/cabinet/appointments/a-1/confirm'),
          statusCode: 409,
        ),
      ),
    );

    final result = await repository.confirm('a-1');

    expect(result.isLeft(), isTrue,
        reason: '409 doit remonter une erreur — plus de faux Right fabriqué');
    result.fold(
      (failure) => expect(failure, isA<ValidationFailure>()),
      (_) => fail('devrait être un Left'),
    );
  });
}
