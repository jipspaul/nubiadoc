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
// #8190 — ce recalage à 1280 était en fait erroné *pour cet écran précis* :
// `design/mockups/v2/INDEX.md` mappe « Consultation au fauteuil » sur la
// maquette **tablette** 2 colonnes (`Praticien Consultation v2.html`,
// fenêtre cible 1258×834 — proche du viewport nominal 1280×800 de l'app) et
// réserve la maquette **PC** 3 colonnes (`Praticien Consultation PC.html`)
// à un écran distinct (« Consultation sur PC (responsive) »), dont la
// fenêtre cible est 1440×900. En retenant 1280 comme seuil fenêtre, #6955
// faisait donc basculer l'écran en 3 colonnes dès le viewport nominal :
// la colonne centrale (schéma dentaire) perdait les ~210 px de la colonne
// « Contexte » qu'elle n'aurait pas dû céder à ce viewport, et la case de
// dent retombait à 14 px de large (code FDI replié, cf. #8035 qui avait déjà
// déplacé ce même symptôme de 9 à 14 px sans le corriger). Même calcul que
// `kCoverageColumnBreakpoint` (treatment_plans/widgets/coverage_column.dart,
// #6626) et `_kOrdonnanceContextBreakpoint` (ordonnances/ordonnance_new_page.dart,
// #6625), qui utilisent déjà 1440 pour ce même type de seuil : 1440 (fenêtre
// cible de la maquette PC) − 251 (chrome fixe de `ProShell`) = 1189.
const kThreeColumnBreakpoint = 1189.0;
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
