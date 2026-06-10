import 'package:equatable/equatable.dart';

import '../models/appointment.dart';

sealed class AppointmentEvent extends Equatable {
  const AppointmentEvent();

  @override
  List<Object?> get props => [];
}

/// Charge la liste des RDV (GET /v1/appointments), filtrée par [tab].
final class AppointmentLoadRequested extends AppointmentEvent {
  const AppointmentLoadRequested({this.tab = AppointmentTab.upcoming});

  final AppointmentTab tab;

  @override
  List<Object?> get props => [tab];
}

/// Charge le détail d'un RDV (GET /v1/appointments/{id}).
final class AppointmentDetailRequested extends AppointmentEvent {
  const AppointmentDetailRequested({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// Prend un RDV (POST /v1/appointments).
final class AppointmentBookRequested extends AppointmentEvent {
  const AppointmentBookRequested({
    required this.providerId,
    required this.startsAt,
    required this.motif,
  });

  final String providerId;
  final DateTime startsAt;
  final String motif;

  @override
  List<Object?> get props => [providerId, startsAt, motif];
}

/// Annule un RDV (POST /v1/appointments/{id}/cancel).
final class AppointmentCancelRequested extends AppointmentEvent {
  const AppointmentCancelRequested({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// Onglets de la liste des RDV.
enum AppointmentTab {
  /// RDV à venir : statuts [requested] + [confirmed].
  upcoming,

  /// Historique : statuts [done] + [cancelled].
  history,
}

