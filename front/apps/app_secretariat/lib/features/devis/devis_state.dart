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

class DevisDetailLoaded extends DevisState {
  const DevisDetailLoaded(this.quote);

  final CabinetQuote quote;

  @override
  bool operator ==(Object other) =>
      other is DevisDetailLoaded && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

class DevisDetailError extends DevisState {
  const DevisDetailError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is DevisDetailError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Envoi du devis au patient en cours (#4537).
class DevisSendInProgress extends DevisState {
  const DevisSendInProgress(this.quote);

  final CabinetQuote quote;

  @override
  bool operator ==(Object other) =>
      other is DevisSendInProgress && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

/// Devis envoyé au patient (confirmation).
class DevisSent extends DevisState {
  const DevisSent(this.quote);

  final CabinetQuote quote;

  @override
  bool operator ==(Object other) => other is DevisSent && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

/// Échec de l'envoi : on reste sur le détail et on signale l'erreur.
class DevisSendFailure extends DevisState {
  const DevisSendFailure({required this.quote, required this.message});

  final CabinetQuote quote;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is DevisSendFailure &&
      other.quote == quote &&
      other.message == message;

  @override
  int get hashCode => Object.hash(quote, message);
}
