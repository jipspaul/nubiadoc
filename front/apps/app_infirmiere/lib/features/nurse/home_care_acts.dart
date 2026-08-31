/// Libellés FR des actes de soin (`ALLOWED_ACTS`, `api/src/nurse/requests.rs:32`)
/// — miroir de `homeCareActs` côté patient
/// (`app_patient/lib/features/home_care/home_care_models.dart:6-11`).
const Map<String, String> homeCareActLabels = {
  'prise_de_sang': 'Prise de sang',
  'pansement': 'Pansement',
  'injection': 'Injection',
  'perfusion': 'Perfusion',
  'toilette': 'Toilette',
  'surveillance': 'Surveillance',
};

/// Libellé FR d'un acte, ou l'identifiant brut si inconnu de la table.
String homeCareActLabel(String act) => homeCareActLabels[act] ?? act;
