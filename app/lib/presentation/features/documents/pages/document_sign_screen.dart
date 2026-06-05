import 'package:flutter/material.dart';

/// Placeholder — document signing screen (deep link target: nubia://documents/:id/sign).
class DocumentSignScreen extends StatelessWidget {
  const DocumentSignScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signature')),
      body: Center(child: Text('Signer document $id')),
    );
  }
}
