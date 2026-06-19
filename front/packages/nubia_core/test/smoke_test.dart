import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_core/nubia_core.dart';

void main() {
  test('ApiConstants.baseUrl est défini', () {
    expect(ApiConstants.baseUrl, isNotEmpty);
  });

  test('ApiConstants.connectTimeout est supérieur à zéro', () {
    expect(ApiConstants.connectTimeout.inSeconds, greaterThan(0));
  });
}
