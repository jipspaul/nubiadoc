import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/src/error/failure.dart';

import 'package:nubia_data/src/remote/cabinet_correspondents/cabinet_correspondents_api.dart';
import 'package:nubia_data/src/repositories/cabinet_correspondents_repository_impl.dart';

class MockCabinetCorrespondentsApi extends Mock
    implements CabinetCorrespondentsApi {}

DioException _validationError({String? field}) => DioException(
      requestOptions: RequestOptions(path: '/v1/cabinet/correspondents'),
      response: Response(
        requestOptions: RequestOptions(path: '/v1/cabinet/correspondents'),
        statusCode: 422,
        data: {
          'code': 'validation_error',
          if (field != null) 'field': field,
        },
      ),
    );

void main() {
  late MockCabinetCorrespondentsApi api;
  late CabinetCorrespondentsRepositoryImpl repo;

  setUp(() {
    api = MockCabinetCorrespondentsApi();
    repo = CabinetCorrespondentsRepositoryImpl(api);
  });

  group('create — 422 par champ (#8064)', () {
    test('field=email → message désigne l\'e-mail, pas le nom', () async {
      when(() => api.create(
            displayName: any(named: 'displayName'),
            specialty: any(named: 'specialty'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
            address: any(named: 'address'),
            rpps: any(named: 'rpps'),
            notes: any(named: 'notes'),
          )).thenThrow(_validationError(field: 'email'));

      final result = await repo.create(displayName: 'Dr Valide', email: 'x');

      final failure = result.fold((f) => f, (_) => null) as ValidationFailure;
      expect(failure.message, "L'adresse e-mail n'est pas valide.");
      expect(failure.message, isNot(contains('nom')));
    });

    test('pas de champ fourni (ancien contrat serveur) → message générique',
        () async {
      when(() => api.create(
            displayName: any(named: 'displayName'),
            specialty: any(named: 'specialty'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
            address: any(named: 'address'),
            rpps: any(named: 'rpps'),
            notes: any(named: 'notes'),
          )).thenThrow(_validationError());

      final result = await repo.create(displayName: 'Dr Valide');

      final failure = result.fold((f) => f, (_) => null) as ValidationFailure;
      expect(failure.message,
          'Le nom du correspondant est obligatoire ou un champ est invalide.');
    });
  });

  group('update — 422 par champ (#8064)', () {
    test('field=display_name → message désigne le nom', () async {
      when(() => api.update(
            any(),
            displayName: any(named: 'displayName'),
            specialty: any(named: 'specialty'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
            address: any(named: 'address'),
            rpps: any(named: 'rpps'),
            notes: any(named: 'notes'),
          )).thenThrow(_validationError(field: 'display_name'));

      final result = await repo.update('corr-1', displayName: '   ');

      final failure = result.fold((f) => f, (_) => null) as ValidationFailure;
      expect(failure.message,
          'Le nom du correspondant est obligatoire ou dépasse la longueur '
          'autorisée.');
    });
  });
}
