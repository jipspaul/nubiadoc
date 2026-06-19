import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

extension PumpApp on WidgetTester {
  /// Wraps [child] in a [MaterialApp] with the Nubia light theme.
  ///
  /// Pass [overrides] (a pre-configured [GetIt] instance) when the widget
  /// under test resolves services via the global [GetIt.instance]; the
  /// harness will reset the global locator before pumping.
  Future<void> pumpApp(Widget child, {GetIt? overrides}) async {
    if (overrides != null) {
      await GetIt.instance.reset();
    }
    await pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: child,
      ),
    );
  }
}
