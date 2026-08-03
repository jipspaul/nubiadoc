/// Table locale acte → statut de dent PROPOSÉ (pré-remplissage de formulaire
/// uniquement, jamais d'écriture automatique — périmètre non-dispositif-
/// médical, docs/06 §E4.8) : après un acte portant une dent, le dialogue de
/// mise à jour d'odontogramme pré-sélectionne ce statut, le praticien valide
/// ou ignore.
///
/// Le vocabulaire de statuts est celui de l'odontogramme
/// (`kToothStatuses`, features/dental_chart/dental_chart_page.dart, miroir
/// de `TOOTH_STATUSES` côté api/src/dental_chart.rs).
library;

/// Mots-clés (minuscules) → statut proposé. Premier match gagnant : l'ordre
/// place les libellés les plus spécifiques en tête (« couronne sur implant »
/// → `implant`, la dent reste implantée ; la couronne n'est qu'une
/// suprastructure).
const _keywordToStatus = <(String, String)>[
  ('implant', 'implant'),
  ('bridge', 'bridge'),
  ('couronne', 'couronne'),
  ('avulsion', 'absent'),
  ('extraction', 'absent'),
  ('obturation', 'obture'),
  ('restauration', 'obture'),
  ('composite', 'obture'),
  ('pulpectomie', 'devitalise'),
  ('endodontique', 'devitalise'),
  ('devitalisation', 'devitalise'),
  ('dévitalisation', 'devitalise'),
];

/// Statut de dent proposé pour un acte, `null` si aucun mot-clé ne matche
/// (dans ce cas aucun dialogue n'est proposé — le praticien passe par
/// l'écran odontogramme s'il veut mettre à jour l'état).
String? suggestedToothStatusForAct({
  required String ccamCode,
  required String label,
}) {
  final normalized = label.toLowerCase();
  for (final (keyword, status) in _keywordToStatus) {
    if (normalized.contains(keyword)) return status;
  }
  return null;
}
