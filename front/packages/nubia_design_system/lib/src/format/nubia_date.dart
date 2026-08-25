/// Foundation de formatage de date/heure partagée (fondation 3, #5128) — un
/// seul helper propriétaire, à utiliser au lieu de réimplémenter un
/// `_formatTimestamp` local par écran (8e occurrence relevée dans
/// l'écosystème avant ce ticket, cf. `grep -rn _formatTimestamp front/apps`).
class NubiaDate {
  const NubiaDate._();

  /// Heure seule, chiffres tabulaires ; ex. `17:42`, `08:12`.
  static String timeOnly(DateTime d) => '${_pad2(d.hour)}:${_pad2(d.minute)}';

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
