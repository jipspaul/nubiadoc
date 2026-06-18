import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('AmountCents', () {
    test('stocke la valeur en centimes', () {
      const a = AmountCents(125000);
      expect(a.value, 125000);
    });

    test('toString contient le signe euro et le séparateur décimal', () {
      final s = const AmountCents(125000).toString();
      expect(s, contains('€'));
      expect(s, contains(','));
    });

    test('égalité structurelle (Equatable)', () {
      expect(const AmountCents(100), const AmountCents(100));
      expect(const AmountCents(100), isNot(const AmountCents(200)));
    });
  });

  group('Failure', () {
    test('NetworkFailure a un message par défaut', () {
      const f = NetworkFailure();
      expect(f.message, isNotEmpty);
    });

    test('ServerFailure expose statusCode et code', () {
      const f = ServerFailure(
        message: 'Internal server error',
        statusCode: 500,
        code: 'internal_error',
      );
      expect(f.statusCode, 500);
      expect(f.code, 'internal_error');
    });

    test('UnauthorizedFailure a un message non vide', () {
      const f = UnauthorizedFailure();
      expect(f.message, isNotEmpty);
    });

    test('ValidationFailure expose les fieldErrors', () {
      const f = ValidationFailure(
        message: 'Champs invalides',
        fieldErrors: {'email': 'format invalide'},
      );
      expect(f.fieldErrors['email'], 'format invalide');
    });

    test('CacheFailure est instanciable', () {
      const f = CacheFailure();
      expect(f, isA<Failure>());
    });
  });
}
