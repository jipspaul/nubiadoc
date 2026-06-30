import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../appointments/appointments_bloc.dart';
import '../appointments/appointments_page.dart';

class BookAppointmentPage extends StatelessWidget {
  const BookAppointmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<AppointmentsBloc>(),
      child: Scaffold(
        key: const Key('book_appointment_scaffold'),
        appBar: AppBar(title: const Text('Booker un RDV')),
        body: const AppointmentsPage(),
      ),
    );
  }
}
