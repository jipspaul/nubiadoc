import 'package:equatable/equatable.dart';

abstract class CabinetBriefEvent extends Equatable {
  const CabinetBriefEvent();

  @override
  List<Object?> get props => [];
}

/// Charge/recharge le brief (#7191). `view` : "day" | "week" | "prostheses".
/// `date` (`YYYY-MM-DD`, défaut aujourd'hui) — même paramètre que l'API.
class CabinetBriefLoadRequested extends CabinetBriefEvent {
  final String view;
  final String? date;

  const CabinetBriefLoadRequested({required this.view, this.date});

  @override
  List<Object?> get props => [view, date];
}

/// Demande l'export PDF du brief actuellement affiché (#7191).
class CabinetBriefPdfRequested extends CabinetBriefEvent {
  const CabinetBriefPdfRequested();
}

/// Consomme le PDF généré (bytes/erreur) une fois partagé/enregistré par la
/// page — même pattern que `AgendaStartedConsultationConsumed`.
class CabinetBriefPdfConsumed extends CabinetBriefEvent {
  const CabinetBriefPdfConsumed();
}
