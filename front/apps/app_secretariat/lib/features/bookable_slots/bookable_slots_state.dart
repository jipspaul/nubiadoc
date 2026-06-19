import 'package:nubia_domain/nubia_domain.dart';

abstract class BookableSlotsState {
  const BookableSlotsState();
}

class BookableSlotsInitial extends BookableSlotsState {
  const BookableSlotsInitial();

  @override
  bool operator ==(Object other) => other is BookableSlotsInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class BookableSlotsLoading extends BookableSlotsState {
  const BookableSlotsLoading();

  @override
  bool operator ==(Object other) => other is BookableSlotsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class BookableSlotsLoaded extends BookableSlotsState {
  const BookableSlotsLoaded(this.slots);

  final List<Slot> slots;

  @override
  bool operator ==(Object other) =>
      other is BookableSlotsLoaded &&
      other.slots.length == slots.length &&
      List.generate(slots.length, (i) => other.slots[i] == slots[i])
          .every((b) => b);

  @override
  int get hashCode => Object.hashAll(slots);
}

class BookableSlotsError extends BookableSlotsState {
  const BookableSlotsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is BookableSlotsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
