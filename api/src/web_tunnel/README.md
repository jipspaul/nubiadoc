# Tunnel web de réservation — pages rendues côté serveur, PAS Flutter web

Ce module sert les 3 pages publiques du tunnel de réservation patient (recherche, fiche praticien,
confirmation — maquette `design/v2-screens/patient-web-tunnel-reservation.png`).

## Décision (noir sur blanc)

**Ces pages sont du HTML rendu côté serveur. Ce n'est pas du Flutter web.**

Motif (verbatim de la maquette) : « Flutter web ne convient pas à ce tunnel » — Flutter web est un
« canevas rendu côté client », le contenu n'existe qu'après exécution du moteur, le premier affichage
pèse plusieurs Mo, et le texte n'étant pas du HTML, l'indexation par les moteurs de recherche est
« au mieux partielle, souvent inexistante ». Or ce tunnel « n'a qu'une raison d'exister : être trouvé ».

C'est une décision d'architecture prise avant la première ligne de code (issue Forgejo #5355), pas après.
Détail complet (contexte, alternatives, conséquences) : `docs/04-architecture.md` ADR-013.

## Ce que ça implique concrètement, ici

- Les handlers de ce module (`search_page`, `provider_page`, `confirm_page`) renvoient du `Html<String>`
  construit côté serveur (`html::page`) — le HTML de la première réponse est déjà complet, sans exécution
  JS requise pour afficher le titre, le contenu et le contexte SEO.
- **Aucune logique métier dupliquée** : les pages appellent directement les mêmes fonctions Rust que l'API
  JSON publique (`marketplace::search_providers`, `marketplace::get_provider`), dans le même process/pool
  DB (monolithe modulaire, ADR-002/012 — pas de second conteneur, pas de backend dédié).
- **Routeur distinct de `/v1/...`** : ces URL humaines (`/dentiste/paris-2e`,
  `/dr-amelie-rousseau-dentiste-paris`, `/reservation/confirmer`) ne sont pas une API versionnée
  (`api/AGENTS.md` règle 5) — elles sont montées sur un port dédié (`WEB_TUNNEL_PORT`), voir `main.rs`.
- **Design system transposé en CSS** : les jetons de couleur (émeraude/stone), l'échelle typographique
  (Inter + Fraunces) et les rayons proviennent de `nubia_design_system` — exprimés en CSS pur dans
  `html.rs` (`NUBIA_CSS`), pas dans un second framework front. Même marque des deux côtés.
- **Aucune donnée de santé exposée** : ces pages ne montrent que l'annuaire public (déjà couvert par
  ADR-011) — nom, spécialité, secteur, créneaux disponibles. Rien de clinique.

## Périmètre volontairement hors de ce module

Le formulaire d'identité et le compte à rebours du hold (page confirmation) nécessitent du JS une fois la
page chargée — seul le HTML initial (titre, paragraphe de contexte, contrat de la page) doit rester
indexable sans JS ; l'interactivité du formulaire est hors scope de cette page vitrine.
