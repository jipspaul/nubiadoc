import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../router/back_or_home_leading.dart';
import '../appointments/appointments_bloc.dart';
import '../appointments/appointments_page.dart';

class BookAppointmentPage extends StatelessWidget {
  const BookAppointmentPage({this.beneficiaryId, super.key});

  // #8257 : `dependent.id` relayé par `AppRouter.book` (`?beneficiaryId=`)
  // quand le tunnel est ouvert depuis la carte d'un proche.
  final String? beneficiaryId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<AppointmentsBloc>(),
      child: Scaffold(
        key: const Key('book_appointment_scaffold'),
        appBar: AppBar(
          title: const Text('Prendre un rendez-vous'),
          leading: backOrHomeLeading(context),
        ),
        body: AppointmentsPage(initialBeneficiaryId: beneficiaryId),
      ),
    );
  }
}
