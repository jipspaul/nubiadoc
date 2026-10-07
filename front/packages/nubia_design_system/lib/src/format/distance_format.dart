/// Formatage des distances partagé entre toutes les apps (`app_patient`,
/// `app_practicien`, `app_secretariat`, …) — seul helper de distance du
/// dépôt, dans l'esprit de [formatQuoteCents] (#4888) : un helper propriétaire
/// unique plutôt que des `toStringAsFixed(1)` dupliqués et insensibles à la
/// locale (#8110).
library;

/// Formate une distance en mètres avec virgule décimale fr-FR, en mètres
/// entiers sous le kilomètre ; ex. `1375` → « 1,4 km », `850` → « 850 m ».
String formatDistanceM(num meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
