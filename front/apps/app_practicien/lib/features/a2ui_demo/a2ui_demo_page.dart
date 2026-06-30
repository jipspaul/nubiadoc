import 'package:flutter/material.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';

class A2uiDemoPage extends StatelessWidget {
  const A2uiDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('A2UI · démo locale')),
      body: SingleChildScrollView(
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
