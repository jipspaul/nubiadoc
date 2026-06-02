# Handoff — Specs écran par écran

> Specs implémentables. Chaque écran : Overview · Layout · Tokens · Composants · États & interactions · Responsive · Edge cases · Motion · A11y · **Critères d'acceptation (Gherkin)**.
> Réfs : composants `01-composants.md` · fondations `00-fondations.md` · stories `../user-stories.md` · IA `../ia-navigation.md`.

---

# A — Recherche & résultats (onglet Rechercher) — US-M01→M08

### Overview
Porte d'entrée de l'app. L'utilisateur cherche un praticien par nom, spécialité, adresse, GPS ou **besoin**. Au-dessus : mini-dashboard perso (prochain RDV, à signer, à régler).

### Layout
- App bar : salutation (`h2` Fraunces) + cloche notifications (trailing).
- Bloc dashboard : 3 `MetricTile` (gap `space/2`).
- `SearchBar` (48) + chip lieu dessous.
- Sections de chips : « Spécialités », « Récents ».
- Au focus de la SearchBar → écran suggestions plein écran (récents, spécialités, mapping besoin→spécialité).
- Résultats : liste de `ProviderCard` ; barre sticky en tête (Filtres · Trier · liste⇄carte).

### Design tokens
| Token | Usage |
|---|---|
| `display`/`h2` | salutation |
| `bg/page` | fond |
| `primary` | chip lieu actif, CTA, badges dispo |
| `space/4` | marge écran ; `space/3` gap liste |
| `radius/md` | SearchBar ; `radius/full` chips |

### Composants
SearchBar · NubiaChip (lieu, spécialités) · MetricTile ×3 · ProviderCard ×N · SegmentedControl (liste/carte) · BottomSheet (filtres, tri).

### États & interactions
| Élément | État | Comportement |
|---|---|---|
| SearchBar | focus | ouvre suggestions ; debounce 250 ms ; résultats live |
| Besoin saisi | match | affiche « → spécialité suggérée » (chip), **sans diagnostic** |
| Chip lieu | tap | demande géoloc (1re fois) → « Autour de moi » + rayon ; sinon saisie adresse |
| Filtres | tap | bottom sheet facettes ; compteur de résultats live ; « Appliquer » |
| Tri | tap | sheet : pertinence/distance/dispo/avis |
| Carte | toggle | bascule vue carte (écran B) |

### Responsive
Mobile : 1 colonne. Tablette/desktop (annuaire web) : 2 colonnes de résultats + carte latérale persistante (split 60/40).

### Edge cases
- **Géoloc refusée** : fallback saisie adresse + message non bloquant.
- **Aucun résultat** : EmptyState « Aucun praticien — élargir la zone / autre spécialité » + bouton.
- **Besoin ambigu** : proposer plusieurs spécialités (ne pas trancher).
- **Connexion lente** : skeleton de 3 ProviderCard.
- **Faute de frappe** : « Vouliez-vous dire… » (typo-tolérance Meilisearch).

### Motion
Suggestions : fade/slide 200 ms. Bascule liste⇄carte : cross-fade 200 ms. Chips de filtre : scale .98 au tap.

### A11y
SearchBar `role=searchbox` + suggestions `listbox` ; résultats annoncés (« 24 résultats ») via live-region ; ProviderCard label complet ; carte non bloquante (liste équivalente).

### Critères d'acceptation
- Étant donné une recherche « dentiste » + « autour de moi », quand les résultats chargent, alors ils sont triés par défaut (pertinence+distance) et chaque carte montre distance + prochaine dispo.
- Étant donné « mal de dent », quand je lance la recherche, alors l'app **suggère** « chirurgien-dentiste · urgence » sans poser de diagnostic.
- Étant donné un filtre « téléconsultation », quand je l'active, alors seuls les praticiens proposant la téléconsult restent, et le compteur se met à jour.

---

# B — Profil praticien & réservation — US-M09→M11

### Overview
Page publique d'un praticien : tout pour décider + réserver un créneau (même nouveau patient).

### Layout
- En-tête : avatar `lg`, nom + badge vérifié RPPS, spécialité.
- Bloc infos : adresse + mini-carte, secteur & tarifs, langues, PMR, présentation (repliable).
- **Disponibilités** : SlotChips par jour (scroll horizontal des jours).
- Avis (note moyenne + extraits).
- CTA sticky bas « Prendre rendez-vous ».
- Réservation (étapes) : Motif → Créneau → (Nouveau patient : infos + consentements) → Confirmation.

### Design tokens
`primary` CTA & créneau sélectionné · `brand/50` bandeaux · `caption` métadonnées · `radius/lg` carte profil.

### Composants
NubiaAvatar `lg` · NubiaBadge (vérifié, secteur, téléconsult) · MapPin (mini) · SlotChip · NubiaSelect (motif) · NubiaButton (sticky) · stepper (BottomSheet ou pages).

### États & interactions
| Élément | État | Comportement |
|---|---|---|
| Créneau | tap | sélection (un seul) → étape suivante |
| Présentation | repliée/dépliée | « voir plus » |
| Réservation | nouveau patient | insère étape infos + consentements obligatoires |
| Confirmation | succès | ajoute le RDV à « Mes RDV », propose pré-check-in |

### Edge cases
- **Aucune dispo en ligne** : CTA → liste d'attente / « être alerté ».
- **N'accepte pas de nouveaux patients** : badge + message, réservation bloquée (ou orientation).
- **Créneau pris entre-temps** : à la confirmation, erreur + réafficher dispos (re-fetch).
- **Session expirée** pendant la résa : sauvegarde du choix, re-login, reprise.

### Motion
Sélection créneau : highlight 120 ms. Passage d'étape : slide horizontal 280 ms. CTA sticky : ombre au scroll.

### A11y
Calendrier de dispos navigable au clavier ; jour/heure annoncés ; étapes = `aria-current` ; erreurs annoncées.

### Critères d'acceptation
- Étant donné un praticien avec dispos, quand je choisis un motif puis un créneau, alors je peux confirmer et le RDV apparaît immédiatement dans « Mes RDV ».
- Étant donné que je suis nouveau patient, quand je réserve, alors je dois fournir le minimum d'infos et accepter les consentements avant confirmation.
- Étant donné un créneau devenu indisponible, quand je confirme, alors un message clair s'affiche et les dispos sont rechargées.

---

# C — Wedge : devis → signature → acompte (onglet Documents) — US-P19, P21, P22 / US-D03→D05

### Overview
Le parcours monétisable. Côté patient : comprendre le devis, signer (eIDAS), payer l'acompte. Détail flux : `../04-ux-flows/01-wedge-devis-signature-acompte.md`.

### Layout (écran Devis)
- App bar « Devis » + StatusPill (À signer).
- AmountHeader : « Total du plan de soins » (`caption`) + montant (`h2`/`display`, tabulaire).
- Bandeau **reste à charge** (`brand/50`).
- Liste des lignes (acte `body` + montant droite, `tabular`).
- Réassurance (cadenas + eIDAS).
- CTA primaire pleine largeur « Signer le devis ».

### Composants
QuoteCard/AmountHeader · NubiaBadge (statut) · ListRow (lignes) · NubiaButton (primary) · écran signature (consentement Checkbox + zone signature) · écran paiement (choix méthode = radios, Apple/Google Pay) · écran confirmation (succès + reçu + prochain RDV).

### États & interactions
| Élément | État | Comportement |
|---|---|---|
| Devis | sent/signed/paid/expired/refused | StatusPill + CTA contextuel |
| Bouton Signer | loading | spinner pendant ouverture procédure eIDAS |
| Paiement | méthode | Apple Pay préselectionné si dispo ; sinon CB |
| Paiement | échec | message + « Réessayer » + autre méthode ; devis reste `signed`, paiement `pending` |
| Devis signé | verrouillé | modification impossible (immuable, SHA-256) |

### Responsive
Mobile : full width, CTA sticky bas. Back-office (création devis) : table éditable (acte/CCAM/dent/montant) + totaux + « Envoyer ».

### Edge cases
- **Reste à charge = 0** : adapter le bandeau (« rien à avancer »).
- **Signature interrompue** : reprise, devis reste `sent`.
- **Hors-ligne** : devis en lecture seule, signature/paiement nécessitent connexion (message).
- **Montant long** (≥ 6 chiffres) : tabulaire, pas de débordement.
- **Devis expiré** : CTA « Demander un nouveau devis ».

### Motion
Transition signer→payer→succès : slide 280 ms. Succès : check circle scale-in 320 ms (`easing/entrance`).

### A11y
Ordre focus : montant → reste à charge → lignes → CTA. Montants avec devise explicite. Statut = pill texte+icône. Erreurs paiement annoncées (assertive).

### Critères d'acceptation
- Étant donné un devis `sent`, quand je signe puis paie l'acompte, alors le devis devient `paid`, un reçu est dans le coffre-fort et le cabinet est notifié en temps réel.
- Étant donné un paiement refusé, quand l'erreur survient, alors le devis reste signé, l'acompte est `pending` et je peux réessayer ou changer de méthode.
- Étant donné un devis `signed`, quand une modification est tentée, alors elle est refusée (immuable).

---

# D — Mes RDV + salle d'attente virtuelle + téléconsultation — US-P07→12, M14→M17

### Overview
Tous les RDV (tous praticiens), gestion, et **jour J** : check-in → file virtuelle → présentiel/téléconsult.

### Layout
- SegmentedControl « À venir / Historique ».
- Liste de cartes RDV (praticien, spécialité, date/heure, lieu **ou** badge téléconsult, statut).
- Détail RDV : infos + actions (modifier/annuler dans délais, itinéraire, pré-check-in).
- **Salle d'attente** : position (`display`/Fraunces), temps estimé, progress, statut check-in, notif à venir.
- **Téléconsult** : zone vidéo (placeholder en attente), statut, test caméra/micro, bouton rejoindre.

### États & interactions
| Élément | État | Comportement |
|---|---|---|
| RDV | confirmé/checked_in/in_progress/done/cancelled/no_show | StatusPill + actions contextuelles |
| Annulation | dans délai / hors délai | autorisée / refusée (message) |
| File virtuelle | position N | mise à jour **temps réel (SSE)** ; notif à ~5 min |
| Appelé | « c'est à vous » | écran/notif « Salle 2 » (présentiel) ou démarrage appel (téléconsult) |
| Téléconsult | attente/prêt/en cours/incident réseau | bouton rejoindre actif quand prêt ; reprise sur coupure |

### Edge cases
- **Retard signalé** par le patient : met à jour la file (ré-allocation possible côté cabinet).
- **Pas de réseau (téléconsult)** : bandeau + tentative de reconnexion.
- **RDV passé non honoré** : statut `no_show`.
- **Plusieurs RDV le même jour** : la salle d'attente cible le bon RDV (sélection).

### Motion
Position file : compteur qui décrémente (fade). Notif « bientôt à vous » : pulsation cloche 1×. Entrée vidéo : fade 200 ms.

### A11y
File = live-region polite (« vous êtes 2e, ~10 min »). Boutons vidéo labellisés. États annoncés. Cibles ≥ 44.

### Critères d'acceptation
- Étant donné un RDV aujourd'hui, quand je fais le check-in, alors je vois ma position dans la file et un temps estimé qui se met à jour en temps réel.
- Étant donné une téléconsultation, quand le praticien démarre, alors je peux rejoindre l'appel après avoir testé caméra/micro.
- Étant donné une annulation hors délai, quand je tente d'annuler, alors l'action est refusée avec un message explicite.

---

# E — Messagerie (patient & cabinet) — US-P15-16, S06-07

### Overview
Échange patient ↔ cabinet ; côté cabinet, file priorisée (triage **visuel** par règles, jamais clinique).

### Layout
- Patient : liste de conversations (avatar cabinet, dernier message, badge urgent, point non-lu) → fil (bulles) + zone de saisie (texte, photo, doc).
- Cabinet : file priorisée (urgents en tête) + actions « Répondre », « Convertir en RDV ».

### États & interactions
Non-lu (titre 500 + point) ; envoi (optimiste + statut) ; pièce jointe (preview + scan antivirus) ; flag urgent (badge `danger`).

### Edge cases
Pièce jointe trop lourde/format refusé ; envoi échoué (réessayer) ; fil vide (EmptyState) ; bandeau 15/SAMU si urgence détectée (sans automatisme clinique).

### A11y
Bulles avec auteur annoncé ; statut d'envoi annoncé ; le flag urgent ne déclenche aucune action clinique automatique.

### Critères d'acceptation
- Étant donné un message contenant un mot-clé d'urgence, quand il arrive côté cabinet, alors il est **affiché en tête** (priorisation visuelle) sans décision clinique automatique.
- Étant donné un message du cabinet, quand je le reçois, alors une notification sans donnée de santé m'avertit et le contenu se charge à l'ouverture (authentifié).

---

# F — Back-office : dashboard secrétariat + salle d'attente live — US-S02, S05

### Overview
Poste de pilotage du cabinet (desktop/tablette). Cloisonnement : pas de contenu clinique pour le secrétariat.

### Layout
Sidebar (240) + contenu : MetricTiles (RDV du jour, urgents, devis en attente) + table « Salle d'attente » (heure, patient, statut live SSE).

### Responsive
Desktop : sidebar fixe. Tablette : rail 72. Mobile pro : drawer + tables→cartes.

### Edge cases
Aucune activité (EmptyState) ; perte de connexion SSE (bandeau + reconnexion) ; forte affluence (liste scrollable, virtualisation).

### A11y
Tables avec en-têtes ; mises à jour live annoncées discrètement ; navigation clavier complète ; cloisonnement des rôles respecté (RBAC).

### Critères d'acceptation
- Étant donné des patients en salle, quand un patient se check-in, alors la table se met à jour en temps réel (SSE) sans rechargement.
- Étant donné le rôle secrétariat, quand j'ouvre une fiche patient, alors le contenu clinique n'est pas accessible (403 / masqué).

> Les écrans secondaires (onboarding, profil/compte, suivi, plan de traitement, passeport, espace financier) suivent le **même gabarit** + la bibliothèque `01-composants.md`. À spécifier au fil de l'implémentation.
