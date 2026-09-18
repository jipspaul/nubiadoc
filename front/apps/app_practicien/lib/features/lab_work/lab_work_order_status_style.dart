import 'package:nubia_design_system/nubia_design_system.dart';

/// Libellés FR des statuts d'un bon de travail prothétique, y compris les
/// statuts d'expédition intercalés par la migration 0274 (#7209) : partagé
/// entre `lab_work_orders_page.dart` (écran de suivi labo) et
/// `prostheses_today_card.dart` (widget dashboard, #7207) pour éviter deux
/// mappings divergents du même statut.
const kLabWorkOrderStatusLabels = <String, String>{
  'sent': 'Envoyé au labo',
  'in_progress': 'En fabrication',
  'shipped': 'Expédié',
  'received': 'Reçu au cabinet',
  'try_in': 'Essayage',
  'returned': 'Retourné',
  'fitted': 'Posé',
};

/// Variante [StatusPill] de chaque statut — `fitted` reste la seule variante
/// `success` (fin de progression), les statuts d'expédition/transit
/// intermédiaires restent `info`/`warning`/`progress`.
const kLabWorkOrderStatusVariants = <String, StatusPillVariant>{
  'sent': StatusPillVariant.info,
  'in_progress': StatusPillVariant.info,
  'shipped': StatusPillVariant.warning,
  'received': StatusPillVariant.progress,
  'try_in': StatusPillVariant.warning,
  'returned': StatusPillVariant.warning,
  'fitted': StatusPillVariant.success,
};
