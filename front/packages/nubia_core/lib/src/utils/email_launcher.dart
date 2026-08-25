import 'package:url_launcher/url_launcher.dart';

/// Lance le client mail du système sur l'adresse donnée (délégation à la
/// plateforme, même mécanisme que [callPhoneNumber]).
///
/// Retourne `true` si la plateforme a pu traiter l'URL, `false` sinon.
Future<bool> sendEmail(String emailAddress) async {
  final uri = Uri(scheme: 'mailto', path: emailAddress);
  return launchUrl(uri);
}
