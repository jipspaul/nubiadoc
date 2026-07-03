import 'kv_store_io.dart' if (dart.library.html) 'kv_store_web.dart' as impl;

/// Petit magasin clé→valeur pour les jetons d'auth.
///
/// Web : localStorage (persiste de façon fiable au rechargement — la version
/// de flutter_secure_storage utilisée échoue au redéchiffrement WebCrypto sur
/// reload, ce qui déconnectait l'utilisateur). Mobile/desktop : keychain
/// sécurisé (flutter_secure_storage). Sélection par import conditionnel.
abstract class KvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Fabrique la bonne implémentation selon la plateforme.
KvStore createKvStore() => impl.createKvStore();
