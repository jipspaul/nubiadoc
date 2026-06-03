# 08 — Back-office V2 : paradigme « Spotlight » + assistant Nubia

> Nouvelle **direction de design** pour le back-office, alternative à la V1 (sidebar classique). Issue des maquettes `mockups/Nubia Spotlight.html` et `mockups/Nubia Comparatif.html`.
> **Statut : proposition à arbitrer** avec Xav. La V1 (sidebar) reste la base validée ; la V2 est une option différenciante. Impacts API : `../docs/06` §WS7, `../docs/05` §10, `../docs/07` §12.

## 1. Le principe
Au lieu de naviguer par une **barre latérale** d'onglets, le praticien/secrétaire ouvre une **barre de recherche centrale** (façon Spotlight macOS / command palette) et :
- **tape pour filtrer** les vues (tableau de bord, agenda, salle d'attente, devis, fiche patient, messagerie, consultation, plan, ordonnance…) ;
- **navigue au clavier** (↑/↓ + Entrée, Échap pour fermer, ⌘K / `/` pour rouvrir) ;
- **ouvre une vue en plein écran par défaut**, réductible en fenêtre, avec **plusieurs fenêtres** simultanées ;
- voit chaque vue ouverte s'ajouter à un **dock** (bas d'écran) — pas de doublon, fermeture possible.

Le contenu des vues est **exactement celui de la V1, sans la barre latérale** (`chrome="window"`). Ce n'est donc pas un autre produit : c'est la **même information, un autre châssis de navigation**.

## 2. « Demander à Nubia » — assistant en langage naturel
Le **premier résultat** de la barre est toujours **« Demander à Nubia »** (badge *IA*). L'utilisateur pose une question en langage naturel et reçoit une **réponse rédigée** + des **actions suggérées**. Exemples câblés dans la maquette :
- « Résume ma journée » → nb de RDV, encaissements, devis en attente, acomptes à relancer, actions suggérées.
- « Quels devis relancer ? » · « Combien encaissé aujourd'hui ? »
- Génération de **vues personnalisées** (ex. un récapitulatif sur mesure).

C'est le **différenciateur** de la V2 (aucun équivalent en V1). Voir les **garde-fous** ci-dessous — c'est un point sensible (conformité + souveraineté IA).

## 3. Mapping user stories (comparatif V1 ⟷ V2)
Le comparatif aligne, pour chaque besoin, l'écran V1 et son équivalent V2 :

| User story | V1 (sidebar) | V2 (Spotlight) |
|---|---|---|
| Piloter l'activité du jour | Tableau de bord | Tableau de bord ouvert en 1 raccourci |
| Salle d'attente temps réel | Écran dédié | Fenêtre « Salle d'attente » |
| Estimer le reste à charge | Devis & paiements | Fenêtre Devis / calculatrice |
| Consulter une fiche patient | Dossier clinique | Fiche en fenêtre |
| **Synthèse langage naturel** | *(pas d'équivalent)* | **Demander à Nubia** |
| Rechercher & accéder | Recherche dans la sidebar | Barre Spotlight persistante |
| Cœur praticien (journée, patients, fauteuil, plan/devis, ordonnance) | Écrans sidebar | Mêmes écrans, en fenêtres |

## 4. Conséquences design
- **Recherche unifiée back-office** : la barre doit chercher des **vues** *et* des **entités** (patients, RDV, devis, documents) → besoin d'un endpoint de recherche cabinet-scoped (cf. `../docs/06` §WS7).
- **Gestionnaire de fenêtres** : état multi-fenêtres (plein écran / réduit / position / dock) = **état client** (Bloc), pas d'API.
- **Innovation sur les contrôles** : contrôles de fenêtre **maison** (pas les pastilles rouge/jaune/vert d'Apple) — pour éviter le plagiat et garder l'identité Nubia.
- **Cohérence design system** : mêmes tokens que la V1 (émeraude, arrondi doux), clair/sombre, Inter ; wallpaper émeraude flouté + glassmorphism (backdrop-blur) pour la barre et le dock.
- **Accessibilité** : la navigation clavier est un **atout** a11y (à auditer en `06-accessibilite/`) ; prévoir focus visibles, rôles ARIA combobox/listbox, annonces lecteur d'écran.

## 5. Garde-fous (assistant Nubia)
- **Souveraineté** : modèle **souverain** (Mistral / Scaleway), pas avant la traction (cf. `CLAUDE.md`, `../docs/01`). Aucune donnée de santé envoyée à un fournisseur hors UE / soumis au Cloud Act.
- **Cloisonnement & RLS** : l'assistant ne lit que les données du **cabinet courant** et **selon le rôle** (un secrétaire n'obtient jamais de contenu clinique via l'assistant). La requête passe par la même couche RLS + RBAC que le reste.
- **Pas de dispositif médical** : l'assistant **n'aide pas à la décision clinique** et ne pose **aucun diagnostic** (cf. `../docs/07` §8). Il agrège de l'**organisationnel/administratif** (RDV, encaissements, relances), pas de l'aide thérapeutique.
- **Humain dans la boucle** : les « actions suggérées » sont **proposées**, jamais exécutées automatiquement. Toute action sensible (relance, envoi) reste un clic explicite.
- **Audit** : chaque requête assistant est journalisée (`audit_log`), sans PII en clair.
- **Zéro hallucination chiffrée non sourcée** : les chiffres affichés proviennent de requêtes réelles, pas de génération libre ; l'IA **met en forme**, elle n'invente pas les données.

## 6. À trancher
1. **V1 vs V2** comme paradigme par défaut du back-office (ou V2 en surcouche optionnelle de la V1 ?).
2. **Périmètre de l'assistant** au lancement : lecture seule (résumés/chiffres) vs. génération de vues vs. déclenchement d'actions (toujours validées).
3. **Séquencement** : l'assistant IA est explicitement **post-traction** (`CLAUDE.md`) → la V2 *sans* assistant (juste Spotlight + fenêtres) est-elle livrable plus tôt ?

> Maquettes : `mockups/Nubia Spotlight.html` (vivant), `mockups/Nubia Comparatif.html` (V1⟷V2 figé). Stories back-office : `user-stories.md` §H-J + §P. Specs API : `../docs/06` §WS7.
