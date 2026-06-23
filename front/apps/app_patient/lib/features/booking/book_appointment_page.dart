import 'package:flutter/material.dart';

class BookAppointmentPage extends StatelessWidget {
  const BookAppointmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booker un RDV')),
      body: const Center(child: Text('Booking flow viendra (FR1.33+)')),
    );
  }
}
