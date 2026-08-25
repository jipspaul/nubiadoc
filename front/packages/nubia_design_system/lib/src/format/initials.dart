/// Initiales à deux lettres à partir d'un nom complet, pour les avatars
/// ([NubiaAvatar]) — partagées entre patients, agenda et salle d'attente
/// (#5163) pour éviter que des tiers homonymes affichent le même monogramme.
///
/// Retire les espaces superflus, garde les deux premières lettres du premier
/// mot pour un nom d'un seul mot, sinon la première lettre du premier et du
/// dernier mot. Un nom vide retombe sur `–` (jamais de chaîne vide).
String initialsFrom(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '–';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length <= 2 ? p : p.substring(0, 2)).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
