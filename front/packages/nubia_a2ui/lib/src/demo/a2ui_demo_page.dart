import 'package:flutter/material.dart';

import '../render/a2ui_renderer.dart';
import '../transport/a2ui_transport.dart';
import 'demo_fixture.dart';

/// A drop-in page that renders the local A2UI demo fixture through the Nubia
/// renderer — no server required. Wired to each app's `/a2ui-demo` route.
class A2uiDemoPage extends StatelessWidget {
  const A2uiDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('A2UI · démo locale')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: A2uiRenderer(
          transport: FixtureTransport(a2uiDemoStream()),
          endpoint: Uri.parse('fixture://demo'),
          onLocalAction: (surfaceId, action, args) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Action A2UI : $action')),
            );
            return true;
          },
        ),
      ),
    );
  }
}
