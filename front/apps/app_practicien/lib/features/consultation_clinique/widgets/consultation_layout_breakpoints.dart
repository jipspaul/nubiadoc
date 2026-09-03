// Quoi : seuils de largeur pilotant la bascule 1/2/3 colonnes de l'écran
// consultation au fauteuil, imposés par la maquette design-v2 (#4935).
// Quand : lus par `consultation_clinique_page.dart` (choix de la Row 2/3
// colonnes) et `patient_identity_bar.dart` (affichage conditionnel de la
// recherche globale).
// Pourquoi : décidés via `LayoutBuilder` sur la largeur *disponible*, jamais
// `MediaQuery`, car l'app peut tourner en écran partagé et se redimensionner
// — regroupés ici pour que les deux fichiers restent alignés sur les mêmes
// valeurs.
// Modes d'échec : #6386 — `kThreeColumnBreakpoint` doit être exprimé dans le
// même référentiel que la largeur *disponible* qu'il compare (le corps de
// `ProShell`, pas la fenêtre) : 1280 px correspondait à la largeur de fenêtre
// entière de la maquette, jamais atteignable sur le corps une fois la barre
// latérale de `ProShell` (250 px + 1 px de séparateur, #5138) déduite — la
// colonne « Contexte » ne pouvait alors apparaître qu'à ~1840 px de fenêtre
// au lieu des 1440 px ciblés. Valeur recalée : 1440 (fenêtre cible de la
// maquette) − 251 (chrome fixe de `ProShell`) = 1189.
const kThreeColumnBreakpoint = 1189.0;
const kTwoColumnBreakpoint = 900.0;
const kContextColumnWidth = 288.0;
// #4964 — 452 px, colonne « Ajouter un acte / Note de séance », maquette
// design-v2 (bloc `.rgt`).
const kSideColumnWidth = 452.0;
