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
// `ProShell`, pas la fenêtre), jamais la largeur de fenêtre brute une fois la
// barre latérale de `ProShell` (250 px + 1 px de séparateur, #5138) déduite.
// #6955 — le recalage de #6386 avait pris 1440 (largeur d'*illustration* de
// la maquette, « APP PRATICIEN · PC 1440 × 900 ») comme fenêtre cible au lieu
// du seuil « ≥ 1280 » qui, pensait-on alors, découlait du tableau générique
// des trois paliers PC/tablette/mobile — la colonne « Contexte » n'apparaissait
// alors qu'à partir de ~1440 px de fenêtre, condamnant toute la bande
// 1280–1440 px (dont 1366×768) au layout tablette 2 colonnes.
// #8190 — #6955 avait été recalé sur la lecture d'`INDEX.md` (qui mappe
// « Consultation au fauteuil » sur la maquette tablette, 1258×834, et la
// maquette PC sur un écran distinct, 1440×900) sans relire le tableau des
// trois paliers de la maquette PC elle-même.
// #8191 (régression) — #8190 avait alors retenu 1440 comme *seuil*, en
// confondant la fenêtre d'*illustration* de la maquette PC avec le seuil
// qu'elle prescrit. Or `Praticien Consultation PC.html` énonce noir sur
// blanc, dans son tableau des trois paliers : « ≥ 1280 · PC · 3 colonnes » —
// 1440 n'est que la largeur à laquelle cette maquette est dessinée (« Les
// 182 px gagnés (1440 contre 1258) »), pas le seuil de bascule. #8191
// condamnait donc à nouveau toute la bande 1280–1439 px (dont 1366×768) au
// layout tablette 2 colonnes.
// #8202 — seuil remis à 1280 (fenêtre), conformément au tableau des trois
// paliers de la maquette PC. Ce recalage ne retombe plus dans le travers de
// #8190 (case de dent écrasée sous le plancher tactile) car #8203 a depuis
// posé un plancher de 44×50 px sur la case, indépendant du seuil : en-deçà
// de la largeur nominale des deux quadrants côte à côte, l'arcade se replie
// au lieu de rétrécir la case. 1280 (fenêtre) − 251 (chrome fixe de
// `ProShell`, #5138) = 1029.
const kThreeColumnBreakpoint = 1029.0;
const kTwoColumnBreakpoint = 900.0;
const kContextColumnWidth = 288.0;
// #4964 — 452 px, colonne « Ajouter un acte / Note de séance » du layout
// **tablette 2 colonnes** (`Praticien Consultation v2.html`, 1258×834, bloc
// `.rgt`). Ne vaut que pour `kTwoColumnBreakpoint` : le layout PC 3 colonnes
// a sa propre maquette avec une colonne de saisie plus étroite, cf.
// `kThreeColumnSideWidth`.
const kSideColumnWidth = 452.0;
// #8035 — avant ce correctif, le layout PC 3 colonnes réutilisait à tort
// `kSideColumnWidth` (452 px, valeur de la maquette *tablette*). Une fois
// `kThreeColumnBreakpoint` recalé à 1280 px de fenêtre (#6955), les 76 px en
// trop volés à la colonne centrale faisaient tomber le schéma dentaire à
// 9 px de large par dent (#8035) à ce seuil. Valeur correcte, maquette PC
// (`Praticien Consultation PC.html`, 1440×900, bloc `.rgt`) : 376 px.
const kThreeColumnSideWidth = 376.0;
