import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The parsed A2UI catalog (`assets/catalog.json`).
///
/// Declares the component types and their prop schemas available to agents.
/// The Flutter renderer validates incoming components against this contract.
class Catalog {
  const Catalog({
    required this.catalogId,
    required this.version,
    required this.instructions,
    required this.components,
  });

  final String catalogId;
  final String version;
  final String instructions;
  final Map<String, dynamic> components;

  Iterable<String> get componentTypes => components.keys;

  /// Returns the declared enum values for a component prop, if any.
  List<String> enumValues(String component, String prop) {
    final comp = components[component] as Map<String, dynamic>?;
    final props = comp?['props'] as Map<String, dynamic>?;
    final p = props?[prop] as Map<String, dynamic>?;
    final values = p?['enum'] as List?;
    return values?.map((e) => e.toString()).toList() ?? const [];
  }

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
        catalogId: json['catalogId'] as String,
        version: json['version'] as String? ?? '0',
        instructions: json['instructions'] as String? ?? '',
        components: (json['components'] as Map).cast<String, dynamic>(),
      );

  static Catalog parse(String jsonStr) =>
      Catalog.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  /// Loads the bundled catalog asset shipped with this package.
  static Future<Catalog> load() async {
    final raw = await rootBundle
        .loadString('packages/nubia_a2ui/assets/catalog.json');
    return parse(raw);
  }
}
