import 'package:flutter/material.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';

class A2uiDemoPage extends StatelessWidget {
  const A2uiDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('A2UI · démo locale')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Moteur de rendu A2UI',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Surface rendue depuis un flux local — aucun serveur requis.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 32),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
          ),
        ],
      ),
    );
  }
}
