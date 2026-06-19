import 'package:nubia_domain/nubia_domain.dart';

abstract class DevisState {
  const DevisState();
}

class DevisInitial extends DevisState {
  const DevisInitial();

  @override
  bool operator ==(Object other) => other is DevisInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class DevisLoading extends DevisState {
  const DevisLoading();

  @override
  bool operator ==(Object other) => other is DevisLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class DevisLoaded extends DevisState {
  const DevisLoaded(this.quotes);

  final List<CabinetQuote> quotes;

  @override
  bool operator ==(Object other) =>
      other is DevisLoaded &&
      other.quotes.length == quotes.length &&
      List.generate(quotes.length, (i) => other.quotes[i] == quotes[i])
          .every((b) => b);

  @override
  int get hashCode => Object.hashAll(quotes);
}

class DevisError extends DevisState {
  const DevisError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is DevisError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
