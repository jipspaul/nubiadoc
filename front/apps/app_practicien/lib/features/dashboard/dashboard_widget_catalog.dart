/// Catalogue des widgets personnalisables du dashboard praticien (#7161) —
/// mêmes identifiants que `known_widgets("pro")` côté API
/// (`api/src/dashboard_layout.rs`), dans l'ordre par défaut avant toute
/// personnalisation.
///
/// `TasksCard` (#7210) n'y figure pas : c'est un aperçu du cabinet entier,
/// pas un widget personnalisable (la personnalisation fine vit dans
/// `TasksPage`).
const List<String> kProDashboardWidgetCatalog = [
  'kpi_tiles',
  'next_patient',
  'today_schedule',
  'pending_actions',
  'prostheses_today',
  'today_notes',
  'week_summary',
  'opportunities',
];

const Map<String, String> kProDashboardWidgetLabels = {
  'kpi_tiles': 'Indicateurs clés',
  'next_patient': 'Patient suivant',
  'today_schedule': 'Planning du jour',
  'pending_actions': 'À traiter',
  'prostheses_today': 'Prothèses du jour',
  'today_notes': 'Notes du jour',
  'week_summary': 'Résumé de la semaine',
  'opportunities': 'Opportunités du moment',
};
