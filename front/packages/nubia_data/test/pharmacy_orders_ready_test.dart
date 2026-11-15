import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/src/error/failure.dart';

import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_orders_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_orders_repository_impl.dart';

class MockPharmacyOrdersApi extends Mock implements PharmacyOrdersApi {}

DioException _dioError(int status, {Map<String, dynamic>? data}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: data,
      ),
    );

void main() {
  late MockPharmacyOrdersApi api;
  late PharmacyOrdersRepositoryImpl repo;

  setUp(() {
    api = MockPharmacyOrdersApi();
    repo = PharmacyOrdersRepositoryImpl(api);
  });

  group('markReady — 409 items_not_prepared distinct de invalid_status (#8586)',
      () {
    test('409 {code: items_not_prepared} → message avec le compte de lignes',
        () async {
      when(() => api.markReady('order-1')).thenThrow(
        _dioError(409, data: {
          'code': 'items_not_prepared',
          'prepared': 0,
          'total': 2,
        }),
      );

      final result = await repo.markReady('order-1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(
            failure.message,
            '0 sur 2 lignes préparées — ouvrez le détail pour les cocher.',
          );
          expect((failure as ServerFailure).statusCode, 409);
          expect(failure.code, 'items_not_prepared');
        },
        (_) => fail('attendu Left'),
      );
    });

    test('409 {code: invalid_status} → message générique inchangé', () async {
      when(() => api.markReady('order-1'))
          .thenThrow(_dioError(409, data: {'code': 'invalid_status'}));

      final result = await repo.markReady('order-1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(
            failure.message,
            'Action impossible dans l’état actuel de la commande.',
          );
          expect((failure as ServerFailure).statusCode, 409);
          expect(failure.code, 'invalid_status');
        },
        (_) => fail('attendu Left'),
      );
    });
  });
}
