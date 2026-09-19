/// Types d'acte couverts par un modèle de consentement (même catalogue que
/// `VALID_ACT_CATEGORIES` côté API, `consent_templates.rs`).
const consentActCategories = <String, String>{
  'chirurgie_orale': 'Chirurgie orale',
  'parodontologie': 'Parodontologie',
  'implantologie': 'Implantologie',
  'prothese_amovible_partielle': 'Prothèse amovible partielle',
  'prothese_amovible_totale': 'Prothèse amovible totale',
  'prothese_fixe_unitaire': 'Prothèse fixe unitaire',
  'prothese_fixe_plurale': 'Prothèse fixe plurale',
  'orthodontie': 'Orthodontie',
  'pedodontie': 'Pédodontie',
  'endodontie': 'Endodontie',
};

String consentActCategoryLabel(String actCategory) =>
    consentActCategories[actCategory] ?? actCategory;
