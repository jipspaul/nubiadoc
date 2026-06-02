# Handoff — Bibliothèque de composants

> Contrat dev : chaque composant = un widget `Nubia*` réutilisable. Mesures en pt (mobile). Tokens : `../03-design-system/01-tokens.md`. États standard : `00-fondations.md` §8.
> Format par composant : **anatomie · mesures · variantes/tailles · états · props (Flutter) · interaction · a11y · do/don't**.

---

## 1. NubiaButton
**Anatomie** : conteneur · (icône 20) · label (`label` 14/500) · (spinner si loading).
**Mesures** : hauteur `sm` 32 · `md` 40 · `lg` 48 ; padding H 16 (md), gap icône-label 8 ; radius `md` 8 ; pleine largeur en CTA mobile.
**Variantes** : `primary` (fill `primary`, texte on-primary) · `secondary` (surface, bordure `border/default`) · `ghost` (transparent, texte `primary`) · `danger` (fill `danger.fg`/texte blanc, ou texte danger sur surface).
**États** : default ; hover → fill `primary/hover` (desktop) ; pressed → `primary/pressed` + scale .98 ; focus → ring ; disabled → bg `neutral/200`, texte `text/tertiary`, opacité 38% ; loading → spinner 16, label masqué, non interactif (largeur figée).
**Props** : `variant`, `size`, `icon?`, `trailingIcon?`, `isLoading`, `isFullWidth`, `onPressed` (null = disabled).
**Interaction** : ripple `motion/fast` ; double-tap protégé pendant loading.
**A11y** : rôle bouton ; cible ≥ 44 ; label explicite (jamais « OK » seul) ; loading annoncé « chargement en cours » ; `Enter`/`Espace`.
**Do/Don't** : ✅ un seul `primary` par écran. ❌ pas de bouton plein rouge pour une action non destructive.

## 2. NubiaTextField
**Anatomie** : label (`label`, au-dessus) · champ (icône leading? · input · trailing?) · helper/erreur (`caption`).
**Mesures** : hauteur 48 ; padding H 12 ; radius `sm` 6 ; bordure 1 (focus 2).
**Variantes** : `text`, `email`, `password` (trailing œil), `search` (leading loupe), `amount` (suffixe €, clavier num), `phone`, `multiline` (min 3 lignes).
**États** : default (bordure `border/default`) ; focus (bordure `primary` + ring) ; filled ; error (bordure `danger.fg` + message + icône) ; disabled (bg `neutral/100`) ; read-only.
**Props** : `label`, `hint`, `helperText?`, `errorText?`, `obscure?`, `keyboardType`, `prefixIcon?`, `suffixIcon?`, `maxLength?`, `enabled`, `onChanged`.
**Interaction** : validation à la soumission + on-blur ; compteur si `maxLength`.
**A11y** : `label` lié au champ ; `errorText` annoncé (live) ; ne jamais signaler l'erreur par la couleur seule.
**Do/Don't** : ✅ message d'erreur actionnable (« E-mail invalide »). ❌ placeholder en guise de label.

## 3. NubiaSelect / Dropdown
**Anatomie** : champ (valeur + chevron) → bottom sheet (mobile) / menu (desktop) avec options.
**Mesures** : comme TextField ; sheet items 48 de haut.
**États** : fermé/ouvert/sélectionné/désactivé ; recherche intégrée si > 8 options.
**Props** : `value`, `items`, `onChanged`, `searchable?`, `placeholder`.
**A11y** : rôle combobox/listbox ; navigation clavier (flèches, Échap) ; option sélectionnée annoncée.

## 4. Toggle / Checkbox / Radio
**Toggle** : 44×24, pouce 18 ; on = `primary`, off = `neutral/300` ; `motion/fast`.
**Checkbox** : 20×20, radius 5 ; coché = fill `primary` + check blanc.
**Radio** : 20, anneau ; sélection `primary`.
**A11y** : rôle switch/checkbox/radio ; état annoncé ; label cliquable.

## 5. NubiaChip (filtre / choix)
**Anatomie** : (icône) · texte (`micro`/`caption`) · (× si removable).
**Mesures** : hauteur 32 ; padding H 12 ; radius `full`.
**Variantes** : `filter` (toggle), `choice` (radio-like), `input` (removable).
**États** : default (bordure `border`) ; selected (bg `brand/50`, bordure `brand/200`, texte `brand/800`) ; disabled.
**A11y** : rôle bouton à bascule ; `aria-pressed` ; groupe = `role=group` labellisé.

## 6. NubiaCard
**Mesures** : bg `surface` ; bordure `border/subtle` 1 ; radius `lg` 12 ; padding 16 (mobile) / 20-24 (desktop) ; ombre `shadow/sm`.
**Variantes** : `static`, `interactive` (hover `shadow/md`, focus ring, pressed scale .99), `selected` (bordure `primary`, bg `brand/50`).
**A11y** : si cliquable → un seul bouton englobant + label décrivant l'action.

## 7. NubiaBadge / StatusPill
**Mesures** : hauteur 22 ; padding H 8 ; radius `full` ; `micro` 12/500 ; icône 12.
**Variantes (couleur sémantique + icône obligatoire)** : `neutral` brouillon · `success` (confirmé/signé/payé) · `warning` (à signer/en attente/retard) · `danger` (urgent/annulé) · `info` (en salle d'attente/téléconsult).
**A11y** : le **texte porte le sens** ; couleur en renfort uniquement.

## 8. NubiaAvatar
**Mesures** : `sm` 30 · `md` 42 · `lg` 58 ; radius `full` ; initiales (`label`/`title`) sur `brand/50`/texte `brand/800`, ou photo.
**Fallback** : initiales si pas de photo ; icône `user` si ni l'un ni l'autre.

## 9. ListRow / ListItem
**Anatomie** : (leading : avatar/icône) · contenu (titre `body`/500 + sous-titre `caption`) · (trailing : badge / chevron / valeur).
**Mesures** : min-height 56 ; padding V 12 ; séparateur `border2` 1.
**États** : default/hover/pressed/selected ; non-lu (titre 500 + point `primary` 8).
**A11y** : ligne entière cliquable ; annoncer l'état (« non lu, urgent »).

## 10. MetricTile (dashboard)
**Anatomie** : (icône 20) · valeur (`h3`/600) · libellé (`caption`).
**Mesures** : bg `bg/page` ou `surface`, bordure `border`, radius `lg`, padding 12 ; grille 2-3 colonnes, gap 8-12.
**Variante** : `alert` (teinte `warning`/`danger` si action requise).
**A11y** : tuile = bouton ; libellé complet (« 2 documents à signer, ouvrir »).

## 11. NubiaAppBar (header écran)
**Mesures** : hauteur 56 + safe-area ; leading back (chevron 24) ; titre (`title` 18/500, centré ou leading) ; actions (icônes 24, cible 44).
**Variantes** : standard · large (titre `h1` qui se réduit au scroll) · transparent (sur héros).
**A11y** : titre = en-tête ; bouton retour labellisé « Retour ».

## 12. NubiaBottomNav (app patient)
**Mesures** : hauteur 56 + safe-area ; 5 items ; icône 24 + label `micro` 12 ; actif = `primary` (icône+label), inactif = `text/tertiary`.
**Items** : Rechercher (`search`) · Mes RDV (`calendar`) · Messages (`message`, badge compteur) · Documents (`folder`, badge) · Profil (`user`).
**Interaction** : tap = switch d'onglet (conserve l'état de pile par onglet) ; re-tap = scroll-to-top.
**A11y** : `role=tab` ; onglet actif annoncé ; badges annoncés (« Messages, 3 non lus »).

## 13. SearchBar (entrée marketplace)
**Anatomie** : leading loupe · input (`body`) · trailing (micro/voix optionnel) ; **chip lieu** séparée dessous (« Autour de moi » / adresse).
**Mesures** : hauteur 48 ; radius `md` 10 ; bordure `border/default`.
**États** : repos (hint « Praticien, spécialité, besoin… ») ; focus → suggestions (récents, spécialités, mapping besoin→spécialité) ; saisie → résultats live.
**A11y** : rôle searchbox ; suggestions = listbox ; effacer labellisé.

## 14. SlotChip (créneau de RDV)
**Mesures** : hauteur 36 ; padding H 12 ; radius `sm` 8 ; `caption`/500.
**États** : disponible (bordure `border`) ; selected (bordure `primary`, bg `brand/50`, texte `brand/800`) ; indisponible (barré/`text/tertiary`, non focusable) ; loading (skeleton).
**A11y** : créneaux indisponibles `aria-disabled` et hors focus ; libellé « mardi 16 juin 14:30 ».

## 15. ProviderCard (résultat de recherche)
**Anatomie** : avatar `md` (photo) · nom (`body`/500) + **badge vérifié RPPS** (check `primary`) · spécialité + distance (`caption`) · prochaine dispo (badge `success`) · badges (secteur, téléconsult, tiers payant) · chevron.
**Mesures** : carte interactive, padding 12, gap 10 ; min-height 84.
**États** : default/hover/pressed ; « complet » (pas de dispo → CTA liste d'attente) ; « n'accepte pas de nouveaux patients » (badge neutre + message).
**A11y** : carte = bouton « Voir le profil de Dr X, chirurgien-dentiste, à 1,2 km, prochaine dispo demain 14:30 ».

## 16. QuoteCard / AmountHeader (le wedge)
**Anatomie** : libellé (`caption`) · montant total (`h2`/`display`, tabulaire) · **reste à charge** en bandeau `brand/50` · lignes (acte + montant) · réassurance (cadenas + « eIDAS ») · CTA primaire.
**Mesures** : padding 16 ; bandeau reste à charge padding 8-10, radius `md`.
**États** : `draft`/`sent`(à signer, badge warning)/`signed`(badge success, CTA paiement)/`paid`/`expired`/`refused`.
**A11y** : montants lisibles + devise explicite ; ordre focus montant → détail → CTA.

## 17. BottomSheet / Modal
**BottomSheet (mobile)** : radius top `xl` 16 ; handle 32×4 ; padding 16 ; slide-up 240 ms ; scrim 45%.
**Modal (desktop)** : centré, max-width 480, radius `lg`, `shadow/lg`.
**États** : ouverture/fermeture (motion) ; dismissible (swipe down / scrim / Échap) sauf actions critiques (confirmation requise).
**A11y** : focus trap ; `Échap` ferme ; focus rendu à l'élément déclencheur ; titre = en-tête.

## 18. Snackbar / Toast
**Mesures** : bas d'écran, marge 16, radius `md`, padding 12-14 ; auto-dismiss 4 s (action 6 s) ; 1 action max.
**Variantes** : info (surface), success, error (icône + couleur sémantique).
**A11y** : live-region polite (assertive pour erreur) ; ne pas véhiculer une info critique uniquement par toast.

## 19. EmptyState
**Anatomie** : icône/illustration (48) · titre (`title`) · sous-texte (`caption`, `text/secondary`) · CTA optionnel.
**Exemples** : « Aucun rendez-vous » + « Trouver un praticien » ; « Aucun document » ; « Aucun résultat — élargir la zone ».
**A11y** : annoncé comme contenu de la zone.

## 20. Skeleton / Loader
**Skeleton** : blocs `neutral/200`, radius selon contenu, shimmer 1200 ms ; reproduit la forme réelle (liste, carte).
**Spinner** : 16 (bouton) / 24 (zone) / plein écran rare.
**Règle** : skeleton pour le chargement initial d'une liste/écran ; spinner pour une action ponctuelle.

## 21. MapPin / cluster (carte)
**Pin** : goutte 26, couleur `primary` ; sélectionné = agrandi + `brand/800`.
**Cluster** : cercle `brand/50` bordure `brand/600`, nombre `micro`/`brand/800`.
**Interaction** : tap pin → mini-card provider (sheet bas) ; « rechercher dans cette zone » au pan/zoom.
**A11y** : alternative liste obligatoire (carte non bloquante) ; pins focusables avec label.

## 22. SegmentedControl (liste ⇄ carte, à venir/historique)
**Mesures** : hauteur 36 ; radius `full` ou `md` ; segment actif fill `surface`/`brand/50`.
**A11y** : `role=tablist` ; segment actif annoncé.

> Tous mappés à un widget `Nubia*`. Implémentation thème : `../03-design-system/03-flutter-theme.md`. Assemblage par écran : `02-ecrans.md`.
