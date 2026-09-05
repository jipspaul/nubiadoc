import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';

/// Bouton retour explicite pour les routes atteignables par URL directe
/// (lien partagé, notification, rechargement de page) : replie vers
/// l'accueil quand la pile de navigation est vide, au lieu de laisser
/// l'écran sans aucune sortie (#6457).
Widget backOrHomeLeading(BuildContext context) {
  return IconButton(
    key: const Key('btn_appbar_back'),
    icon: const Icon(Icons.arrow_back),
    tooltip: 'Retour',
    onPressed: () =>
        context.canPop() ? context.pop() : context.go(AppRouter.home),
  );
}
