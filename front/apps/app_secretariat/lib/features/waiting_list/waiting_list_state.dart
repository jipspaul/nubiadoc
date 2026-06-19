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
