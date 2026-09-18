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
  (`api/AGENTS.md` règle 5) — pas de préfixe `/v1`. Servies depuis le même port que l'API (`APP_PORT`,
  routeur mergé dans `main.rs`) plutôt qu'un port dédié séparé (#5628 : un second port n'était raccordé à
  aucun nom de domaine en production, rendant ces pages injoignables malgré un code fonctionnellement
  correct — le Caddy réel de l'hôte, hors dépôt, proxie déjà tout `APP_PORT` sans filtre de chemin).
- **Design system transposé en CSS** : les jetons de couleur (émeraude/stone), l'échelle typographique
  (Inter + Fraunces) et les rayons proviennent de `nubia_design_system` — exprimés en CSS pur dans
  `html.rs` (`NUBIA_CSS`), pas dans un second framework front. Même marque des deux côtés.
- **Aucune donnée de santé exposée** : ces pages ne montrent que l'annuaire public (déjà couvert par
  ADR-011) — nom, spécialité, secteur, créneaux disponibles. Rien de clinique.

## Page de confirmation (`/reservation/confirmer`)

- `GET ?providerId=…&slotId=…` : résout le praticien (`marketplace::get_provider`) et le créneau
  (`marketplace::search_slots`, mêmes fonctions que les pages amont), affiche le récapitulatif réel
  (praticien, date, heure) et un **formulaire HTML classique** (prénom, nom, naissance, téléphone, email,
  motif facultatif, case de consentement) — sans aucun JS (CSP du tunnel).
- `POST` (corps `application/x-www-form-urlencoded`) : crée le compte patient, pose le hold puis la
  réservation en appelant directement `auth::register::create_patient_account`, `marketplace::hold_slot`
  et `bookings::create_booking` — exactement le funnel de l'app patient, aucune logique dupliquée. Un email
  de définition de mot de passe est envoyé (mécanisme de `POST /v1/auth/password/forgot`).
- **Hold** : `slot_holds.user_id` est `NOT NULL → app_user`, un hold n'existe donc qu'au nom d'un compte.
  Le `GET` ne pose rien et la page ne dit jamais « votre créneau est retenu » (#6954/#6826/#6733) : elle
  annonce un créneau *disponible* qui sera réservé à la validation.
- Replis : sans `providerId`/`slotId` (ou UUID malformés) → **404** + lien vers la recherche ; praticien
  inconnu → **404** ; créneau perdu (pris, retenu par un autre visiteur, hold expiré, passé, créneau d'un
  autre praticien) → **410** + lien retour vers la fiche du praticien ; formulaire incomplet ou sans
  consentement → **422** (rien n'est écrit) ; email déjà associé à un compte → **409**.
- Tests d'intégration : `api/tests/web_tunnel_confirm.rs`.
