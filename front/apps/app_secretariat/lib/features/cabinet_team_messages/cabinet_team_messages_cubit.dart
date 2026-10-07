//! Cubit de l'écran de messagerie interne d'équipe (#4156) — distinct de la
//! messagerie patient (`cabinet_messaging`). Fil unique par cabinet : charge
//! les messages (`GET .../messages`), permet d'en envoyer un (`POST`), puis
//! recharge le fil pour rester la source de vérité serveur (pas de merge
//! optimiste local — le fil est court/peu fréquent, un aller-retour est
//! largement assez rapide pour l'UX).

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CabinetTeamMessagesState extends Equatable {
  const CabinetTeamMessagesState();

  @override
  List<Object?> get props => [];
}

class CabinetTeamMessagesLoading extends CabinetTeamMessagesState {
  const CabinetTeamMessagesLoading();
}

class CabinetTeamMessagesError extends CabinetTeamMessagesState {
  const CabinetTeamMessagesError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class CabinetTeamMessagesLoaded extends CabinetTeamMessagesState {
  const CabinetTeamMessagesLoaded({
    required this.messages,
    this.practitioners = const [],
    this.practitionersInConsultation = const {},
    this.staffCount = 0,
    this.sending = false,
    this.sendError,
  });

  final List<CabinetTeamMessage> messages;

  /// Roster réel du cabinet (#6245) : remplace les identités de maquette
  /// figées du panneau « Équipe » — même source que l'agenda secrétariat,
  /// déjà accessible sans restriction admin.
  final List<CabinetPractitioner> practitioners;

  /// Ids des praticiens ayant un RDV en cours à l'instant du chargement
  /// (#7668) : même dérivation que `PractitionerToday.isInConsultation` du
  /// tableau de bord (`dashboard_bloc.dart`), à partir de l'agenda du jour —
  /// aucun champ de présence dédié en base.
  final Set<String> practitionersInConsultation;

  /// Effectif du staff (secrétariat/assistanat) du cabinet (#6862) : agrégé
  /// depuis `GET /cabinet/secretariats/:id/members`, accessible sans
  /// restriction admin — contrairement au roster, l'endpoint ne porte pas
  /// encore les noms, donc ce n'est qu'un compte, pas une liste nominative.
  final int staffCount;
  final bool sending;
  final String? sendError;

  /// Consigne(s) épinglée(s) (#5130), dérivée(s) du fil — pas de champ dédié
  /// côté cubit, `messages` reste la source de vérité serveur.
  List<CabinetTeamMessage> get pinnedMessages =>
      messages.where((m) => m.pinned).toList();

  CabinetTeamMessagesLoaded copyWith({
    List<CabinetTeamMessage>? messages,
    List<CabinetPractitioner>? practitioners,
    Set<String>? practitionersInConsultation,
    int? staffCount,
    bool? sending,
    String? sendError,
    bool clearSendError = false,
  }) =>
      CabinetTeamMessagesLoaded(
        messages: messages ?? this.messages,
        practitioners: practitioners ?? this.practitioners,
        practitionersInConsultation:
            practitionersInConsultation ?? this.practitionersInConsultation,
        staffCount: staffCount ?? this.staffCount,
        sending: sending ?? this.sending,
        sendError: clearSendError ? null : (sendError ?? this.sendError),
      );

  @override
  List<Object?> get props => [
        messages,
        practitioners,
        practitionersInConsultation,
        staffCount,
        sending,
        sendError,
      ];
}

class CabinetTeamMessagesCubit extends Cubit<CabinetTeamMessagesState> {
  CabinetTeamMessagesCubit({
    required ListCabinetTeamMessagesUseCase listMessages,
    required SendCabinetTeamMessageUseCase sendMessage,
    required ListCabinetPractitionersUseCase listPractitioners,
    required GetCabinetAgendaUseCase getAgenda,
    required ListSecretariatsUseCase listSecretariats,
    required ListSecretariatMembersUseCase listSecretariatMembers,
  })  : _list = listMessages,
        _send = sendMessage,
        _listPractitioners = listPractitioners,
        _getAgenda = getAgenda,
        _listSecretariats = listSecretariats,
        _listSecretariatMembers = listSecretariatMembers,
        super(const CabinetTeamMessagesLoading()) {
    load();
  }

  final ListCabinetTeamMessagesUseCase _list;
  final SendCabinetTeamMessageUseCase _send;
  final ListCabinetPractitionersUseCase _listPractitioners;
  final GetCabinetAgendaUseCase _getAgenda;
  final ListSecretariatsUseCase _listSecretariats;
  final ListSecretariatMembersUseCase _listSecretariatMembers;

  Future<void> load() async {
    emit(const CabinetTeamMessagesLoading());
    final messagesFuture = _list();
    final practitionersFuture = _listPractitioners();
    final agendaFuture = _agendaToday();
    final staffCountFuture = _staffCount();
    final result = await messagesFuture;
    final practitioners = (await practitionersFuture).fold(
      (_) => const <CabinetPractitioner>[],
      (p) => p,
    );
    final practitionersInConsultation = await agendaFuture;
    final staffCount = await staffCountFuture;
    result.fold(
      (failure) => emit(CabinetTeamMessagesError(failure.message)),
      (messages) => emit(CabinetTeamMessagesLoaded(
        messages: messages,
        practitioners: practitioners,
        practitionersInConsultation: practitionersInConsultation,
        staffCount: staffCount,
      )),
    );
  }

  /// Effectif du staff (secrétariat/assistanat) du cabinet (#6862) : agrège
  /// les membres actifs de chaque secrétariat (`GET .../:id/members`,
  /// accessible sans restriction admin — cf. docstring [staffCount] sur
  /// [CabinetTeamMessagesLoaded]). Best-effort comme le roster praticiens
  /// ci-dessus : un échec, partiel ou total, laisse juste le compteur à 0
  /// plutôt que de casser l'écran.
  Future<int> _staffCount() async {
    final secretariats = (await _listSecretariats()).fold(
      (_) => const <Secretariat>[],
      (s) => s,
    );
    final results = await Future.wait([
      for (final secretariat in secretariats)
        _listSecretariatMembers(secretariat.id),
    ]);
    return results.fold<int>(
      0,
      (sum, result) => sum + result.fold((_) => 0, (members) => members.length),
    );
  }

  /// Ids des praticiens ayant un RDV en cours à l'instant présent (#7668) —
  /// best-effort : un échec de l'agenda laisse juste l'état de présence
  /// vide plutôt que de casser l'écran (même logique que le roster
  /// praticiens ci-dessus).
  Future<Set<String>> _agendaToday() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final result = await _getAgenda(weekStartDate);
    return result.fold(
      (_) => const <String>{},
      (entries) => {
        for (final entry in entries)
          if (!entry.isFree &&
              !entry.isCancelled &&
              !now.isBefore(entry.startsAt) &&
              now.isBefore(entry.endsAt))
            entry.practitionerId,
      },
    );
  }

  Future<void> send(String body) async {
    final current = state;
    if (current is! CabinetTeamMessagesLoaded) return;
    emit(current.copyWith(sending: true, clearSendError: true));
    final result = await _send(body);
    await result.fold(
      (failure) async =>
          emit(current.copyWith(sending: false, sendError: failure.message)),
      (_) => load(),
    );
  }
}
