import 'package:url_launcher/url_launcher.dart';

/// Lance l'appel téléphonique du numéro donné via le composeur du système
/// (délégation à la plateforme, même mécanisme que l'ouverture de document).
///
/// Retourne `true` si la plateforme a pu traiter l'URL, `false` sinon.
Future<bool> callPhoneNumber(String phoneNumber) async {
  final uri = Uri(scheme: 'tel', path: phoneNumber);
  return launchUrl(uri);
}
