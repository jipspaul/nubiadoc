abstract class DevisEvent {
  const DevisEvent();
}

class DevisLoadRequested extends DevisEvent {
  const DevisLoadRequested();
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
