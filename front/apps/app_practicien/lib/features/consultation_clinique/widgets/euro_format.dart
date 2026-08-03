/// Formatte un montant en centimes vers un libellé euros (« 45,29 € » style
/// existant : point décimal conservé pour ne pas changer les assertions e2e).
String formatEuros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';
