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

/// Relance d'un devis `sent` en cours (#6970).
class DevisRemindInProgress extends DevisState {
  const DevisRemindInProgress(this.quote);

  final CabinetQuote quote;

  @override
  bool operator ==(Object other) =>
      other is DevisRemindInProgress && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

/// Relance envoyée au patient (confirmation, #6970). Le statut du devis ne
/// change pas (reste `sent`) — seule une notification part au patient.
class DevisReminded extends DevisState {
  const DevisReminded(this.quote);

  final CabinetQuote quote;

  @override
  bool operator ==(Object other) => other is DevisReminded && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

/// Échec de la relance (#6970).
class DevisRemindFailure extends DevisState {
  const DevisRemindFailure({required this.quote, required this.message});

  final CabinetQuote quote;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is DevisRemindFailure &&
      other.quote == quote &&
      other.message == message;

  @override
  int get hashCode => Object.hash(quote, message);
}

/// Récupération de l'URL du PDF en cours (#6952).
class DevisPdfDownloadInProgress extends DevisState {
  const DevisPdfDownloadInProgress(this.quote);

  final CabinetQuote quote;

  @override
  bool operator ==(Object other) =>
      other is DevisPdfDownloadInProgress && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

/// URL signée obtenue (#6952) — le listener de la page ouvre l'onglet puis
/// revient à une liste sans URL en attente (évite de rouvrir l'onglet à
/// chaque rebuild, même pattern que `FinancialQuoteDetail.documentUrl`).
class DevisPdfDownloadReady extends DevisState {
  const DevisPdfDownloadReady({required this.quote, required this.url});

  final CabinetQuote quote;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is DevisPdfDownloadReady &&
      other.quote == quote &&
      other.url == url;

  @override
  int get hashCode => Object.hash(quote, url);
}

/// Échec de la récupération du PDF (#6952) — inclut le cas où le devis
/// signé n'a pas encore de `documentId` (PDF pas encore généré côté back).
class DevisPdfDownloadFailure extends DevisState {
  const DevisPdfDownloadFailure({required this.quote, required this.message});

  final CabinetQuote quote;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is DevisPdfDownloadFailure &&
      other.quote == quote &&
      other.message == message;

  @override
  int get hashCode => Object.hash(quote, message);
}
