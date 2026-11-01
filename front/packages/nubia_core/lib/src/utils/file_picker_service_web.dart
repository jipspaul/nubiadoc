// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Web : `FilePicker.platform.saveFile` ne livre rien dans cette config
/// (#8533, régression de #8530) — il construit le blob (`createObjectURL`)
/// mais ne pose aucune ancre `download`, n'appelle pas
/// `showSaveFilePicker` et ne lève pas d'exception, donc le clic reste
/// silencieux. On livre ici explicitement via une ancre `<a download>`
/// cliquée par programme, comme le faisait `Share.shareXFiles` en repli
/// avant #8530.
Future<String?> saveFileImpl({
  required Uint8List bytes,
  required String fileName,
}) async {
  final body = html.document.body;
  if (body == null) {
    // Pas de DOM exploitable : impossible de livrer le fichier — on lève
    // pour que l'appelant retombe sur son fallback (snackbar d'échec)
    // plutôt que de rester silencieux comme avant ce correctif.
    throw StateError('saveFile: document.body indisponible sur web.');
  }
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    body.children.add(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
  // Pas de chemin local exposé par le téléchargement navigateur.
  return null;
}
