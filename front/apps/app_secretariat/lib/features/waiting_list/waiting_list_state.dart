import 'package:nubia_domain/nubia_domain.dart';

abstract class WaitingListState {
  const WaitingListState();
}

class WaitingListInitial extends WaitingListState {
  const WaitingListInitial();

  @override
  bool operator ==(Object other) => other is WaitingListInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class WaitingListLoading extends WaitingListState {
  const WaitingListLoading();

  @override
  bool operator ==(Object other) => other is WaitingListLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class WaitingListLoaded extends WaitingListState {
  const WaitingListLoaded(this.entries);

  final List<WaitingListEntry> entries;

  @override
  bool operator ==(Object other) =>
      other is WaitingListLoaded &&
      other.entries.length == entries.length &&
      List.generate(entries.length, (i) => other.entries[i] == entries[i])
          .every((b) => b);

  @override
  int get hashCode => Object.hashAll(entries);
}

class WaitingListError extends WaitingListState {
  const WaitingListError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is WaitingListError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

class WaitingListOfferSuccess extends WaitingListState {
  const WaitingListOfferSuccess();

  @override
  bool operator ==(Object other) => other is WaitingListOfferSuccess;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// #4536 : échec d'une action « Combler » sur une entrée précise. Distinct de
/// [WaitingListError] (échec du CHARGEMENT de la liste, qui lui n'a rien à
/// montrer) — ici la liste reste affichée, seul un feedback ponctuel
/// (snackbar) signale l'échec. Porte [entries] pour que l'écran continue de
/// rendre la liste au lieu de basculer sur l'état d'erreur plein écran.
class WaitingListOfferError extends WaitingListState {
  const WaitingListOfferError(this.message, this.entries);

  final String message;
  final List<WaitingListEntry> entries;

  @override
  bool operator ==(Object other) =>
      other is WaitingListOfferError &&
      other.message == message &&
      other.entries.length == entries.length;

  @override
  int get hashCode => Object.hash(message, entries.length);
}
