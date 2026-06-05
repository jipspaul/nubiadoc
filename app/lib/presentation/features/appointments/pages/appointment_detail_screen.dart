import 'package:flutter/material.dart';

/// Placeholder — appointment detail screen (deep link target: nubia://appointments/:id).
class AppointmentDetailScreen extends StatelessWidget {
  const AppointmentDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail RDV')),
      body: Center(child: Text('RDV $id')),
    );
  }
}
