import 'package:nubia_domain/nubia_domain.dart';

abstract class DevisEvent {
  const DevisEvent();
}

class DevisLoadRequested extends DevisEvent {
  const DevisLoadRequested();
}

/// Crée un devis brouillon (#6757) à partir d'un patient et de lignes
/// saisies dans le dialogue « Nouveau devis » (`widgets/new_quote_dialog.dart`)
/// — jusque-là, l'écran gérait le cycle de vie de devis déjà existants sans
/// offrir aucun point d'entrée en création, alors que l'API
/// (`POST /v1/cabinet/quotes`) le permet déjà.
class DevisCreateRequested extends DevisEvent {
  const DevisCreateRequested({required this.patientId, required this.items});

  final String patientId;
  final List<QuoteLineItem> items;
}

class DevisDetailLoadRequested extends DevisEvent {
  const DevisDetailLoadRequested(this.id);

  final String id;
}

/// #4537 : envoie un devis brouillon au patient pour signature. Le back
/// (`POST /v1/cabinet/quotes/:id/send`) autorise déjà `secretary+` — cet
/// événement expose côté secrétariat une action qui n'existait jusque-là
/// que côté praticien.
class DevisSendRequested extends DevisEvent {
  const DevisSendRequested(this.id);

  final String id;
}

/// #6970 : relance un devis déjà `sent` en attente de signature. Distinct de
/// [DevisSendRequested] (envoi initial d'un brouillon) — `POST
/// /v1/cabinet/quotes/:id/send` est un no-op sur un devis déjà `sent`, le
/// bouton « Relancer » de chaque ligne doit appeler l'endpoint dédié
/// `POST /v1/cabinet/quotes/:id/remind`.
class DevisRemindRequested extends DevisEvent {
  const DevisRemindRequested(this.id);

  final String id;
}

/// #6952 : télécharge le PDF d'un devis signé (bouton « PDF » de la ligne
/// `signed`/`paid`) — jusque-là câblé sur le même callback que le tap de
/// ligne, il n'ouvrait que le volet de détail sans jamais produire de PDF.
class DevisDownloadPdfRequested extends DevisEvent {
  const DevisDownloadPdfRequested(this.id);

  final String id;
}
