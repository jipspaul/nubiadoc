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
