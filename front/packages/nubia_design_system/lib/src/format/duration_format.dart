/// Formate une attente en minutes : minutes seules sous 60 minutes, heures +
/// minutes deux chiffres au-delà — ex. `45` → « 45 min », `1355` → « 22h35 ».
/// Partagé entre les apps pour éviter la minute brute interpolée telle
/// quelle sur les longues attentes (#7298).
String formatWaitMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = (minutes % 60).toString().padLeft(2, '0');
  return '${hours}h$remainder';
}
