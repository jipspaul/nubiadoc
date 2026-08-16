import 'package:url_launcher/url_launcher.dart';

/// Ouvre l'itinéraire vers [destinationQuery] (adresse ou nom de lieu) dans
/// l'application de cartographie du système, via le lien universel Google
/// Maps (même mécanisme que [callPhoneNumber] : délégation à la plateforme).
///
/// Retourne `true` si la plateforme a pu traiter l'URL, `false` sinon.
Future<bool> openMapsDirections(String destinationQuery) async {
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': destinationQuery,
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
