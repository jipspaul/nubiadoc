import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';

void main() {
  final catalog = Catalog.parse(
    File('assets/catalog.json').readAsStringSync(),
  );
  final registry = ComponentRegistry.nubiaDefault();

  test('every catalog component type resolves in the default registry', () {
    final missing = catalog.componentTypes
        .where((type) => !registry.contains(type))
        .toList();
    expect(missing, isEmpty,
        reason: 'Catalog components without a renderer mapping: $missing');
  });

  test('DataModel resolves JSON-pointer paths', () {
    final model = DataModel({
      'patient': {'name': 'Camille'},
      'items': [
        {'title': 'A'},
        {'title': 'B'},
      ],
    });
    expect(model.get('/patient/name'), 'Camille');
    expect(model.get('/items/1/title'), 'B');
    expect(model.get('/missing'), isNull);
  });

  test('Binding resolves {path} props against the data model', () {
    final model = DataModel({'title': 'Hello'});
    final resolved = Binding.resolveProps(
      {
        'value': {'path': '/title'},
        'variant': 'primary',
      },
      model,
    );
    expect(resolved['value'], 'Hello');
    expect(resolved['variant'], 'primary');
  });
}
