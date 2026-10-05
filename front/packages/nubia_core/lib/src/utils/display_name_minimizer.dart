/// Réduit un nom complet (« Marc Dubois ») à la forme minimisée
/// « Prénom N. » (« Marc D. ») attendue par les contrats API qui diffusent
/// l'identité du patient à des tiers n'ayant pas forcément de lien de soin
/// établi (ex. `patient_display_name` vu par les infirmières sollicitées
/// lors d'une demande de visite à domicile) — ne jamais transmettre le nom
/// de famille complet à ces destinataires.
String minimizeDisplayName(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  final firstName = parts.first;
  final lastInitial = parts.last[0].toUpperCase();
  return '$firstName $lastInitial.';
}
