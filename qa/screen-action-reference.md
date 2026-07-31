# QA — Carte de référence Écran → Action → Effet (run humain 2026-07-30)

> **But** : donner au **prochain run QA (automatique)** une carte exploitable de chaque
> app déployée — pour chaque écran atteint : les éléments interactifs, l'action jouée,
> l'effet réel observé (navigation / requête HTTP+code / changement d'état) et le verdict
> OK/BUG. Objectif : **repartir de cette carte au lieu de redécouvrir l'app** à chaque fois.
>
> Méthode : playbook `qa/human-qa-playbook.md` (login à la main, screenshot + jugement
> humain de chaque écran, §9 balayage exhaustif, §8 une issue Forgejo par bug).
> Screenshots dans `qa/screenshots/<app>/` (référencés par nom dans les tableaux).

## 0. Notes techniques transverses (à lire avant de rejouer)

- **Apps = Flutter web (CanvasKit)** → pas de DOM cliquable. On active l'arbre sémantique
  puis on **clique aux coordonnées** repérées à l'œil sur le screenshot (approche §2 du
  playbook). Driver : `qa/scripts/pdrv.mjs` (dans le repo-outil `/workspace/planner-cwd/qa`).
- **URL non fiable comme indicateur de nav** : le praticien garde `/` pour toutes les routes ;
  l'arbre sémantique se **réduit à « N »/« Retour »** après une navigation in-app → **le
  screenshot est la source de vérité**, pas le dump.
- **Login à la main** : formulaires `E-mail (professionnel) / Mot de passe / Se connecter`.
  ⚠️ **Piège harness** : le 1er caractère tapé peut être perdu (Flutter web) → **relire la
  valeur du champ et retaper si faux**. Ne JAMAIS déposer ce flake comme bug (ex. pharmacie
  a d'abord semblé refuser `Nubia2026!` car le « N » était mangé — l'API accepte, cf. §5).
- **Session courte** : l'access token JWT expire **~15 min**. Le refresh via un state file
  partagé est **à usage unique** (rotation du refresh token) → en usage concurrent, les
  sessions s'invalident mutuellement (`401`, écran « Session expirée »). **Impact réel app**
  côté patient : le refresh_token n'est **pas** utilisé du tout (→ issue **#4533**). Pour
  rejouer : re-login juste avant chaque batch et travailler vite (< 15 min), un state file
  par consommateur.
- **Données seed = polluées QA** : Marc Dubois a `Solde : -985462,23 €`, `Lapins : 19`,
  des dizaines de PDF `scan.pdf/x.pdf`, plans « QA-… », etc. Ce sont des **données**, pas
  des bugs (ne pas déposer). L'agenda/dashboard du **jour** (30/07) est vide → naviguer sur
  la semaine (lundi) ou ouvrir un patient pour trouver de la donnée.

### Index des issues (ce run)
| # | App | Sév. | Résumé |
|---|---|---|---|
| 4531 | pharmacie | bloquant | App 100% inaccessible — `POST /v1/auth/select-pharmacy-context` 403 malgré session valide |
| 4532 | patient | gênant | Modifier RDV : créneaux trop proches → `PATCH /appointments` 409 `too_late` + msg générique |
| 4533 | patient | gênant | Session : refresh_token présent mais **non utilisé** → 401 → éjection /login (~15 min) |
| 4534 | patient | ux | Prise de RDV : pas d'écran récap « RDV confirmé », juste un snackbar fugace |
| 4535 | secretariat | gênant | Agenda « Confirmer » (RDV en conflit) → 409 **en silence**, aucun feedback |
| 4536 | secretariat | gênant | Liste d'attente « Combler » → 409 + **efface la liste** par une erreur plein écran |
| 4537 | secretariat | ux | Devis **lecture seule** (aucune action créer/envoyer, même brouillon) |
| 4538 | secretariat | cosmétique | Messagerie interne : **Entrée n'envoie pas** le message |
| 4539 | praticien | ux | **« Démo A2UI »** — écran de démo dev exposé dans la nav prod |
| 4540 | praticien | ux | **« Créer un RDV »** depuis une conversation = impasse (« Aucun créneau disponible ») |
| 4541 | praticien | gênant | **Impossible de créer une ordonnance par clic** (tab renvoie fiche, fiche sans bouton) |
| 4542 | praticien | cosmétique | Liste Patients : patients **sans nom** affichés « ? » + ligne vide |
| 4120 (commenté) | praticien | — | Décompte séances par phase **non exposé dans l'UI** (data-point QA ajouté) |

### Features « fraîchement mergées » = issues backlog OUVERTES (⇒ absence UI attendue, PAS un bug)
Vérifié : ces items correspondent à des **issues Forgejo encore ouvertes** → leur UI
partielle/absente est **normale**, ne pas re-déposer :
- **#4141** « formulaire d'ajout d'implant à la fiche » → **absent** de la fiche. Les implants
  sont représentés autrement : **état « Implant » de l'odontogramme** (Schéma dentaire) qui,
  lui, **fonctionne et persiste** (cf. praticien). Chip document « Passeport implantaire » existe.
- **#4132** « bouton Renouveler sur les ordonnances » → **aucune UI** (0 occurrence dans le code Dart).
- **#4120** « décompte séances à la complétion d'une consultation liée à une phase » → back
  peut-être mergé, **rien dans l'UI** ne montre un décompte de séances (phases = titre+statut
  seulement). Commenté sur #4120.
- **#4072 / #4163** « échéanciers de paiement / provider Alma » → **pas dans l'UI praticien**
  (patient-side : `POST /v1/payments/intent` avec mode `deposit|installment|full`, cf. patient).
- **#4128** « bordereau de remise en banque (chèques) » → **pas exposé** côté secrétariat (§4).

---

## 1. PRATICIEN — https://praticien.doc.nubia-link.com
Compte : `hugo.marin@cabinet-lyon.test`. **Nav = rail gauche vertical**, icônes à `x≈57`,
`y` : Tableau de bord 92 · Agenda 156 · Salle d'attente 200 · Patients 244 · Consultation 288 ·
Ordonnances 332 · Devis 376 · Stock 420 · Inventaire 464 · Labo 508 · Messages 552 ;
bas : Messagerie interne 787 · Démo A2UI 828 · **Se déconnecter 868 (ne pas cliquer)**.
Fiche patient : ouverte via Patients → tap ligne ; page scrollable (pas d'onglets), boutons
d'action en bas.

### 1.1 Tableau de bord
| Élément | Action | Effet observé | Screenshot | OK/BUG |
|---|---|---|---|---|
| 4 cartes métriques (RDV auj / Salle d'attente / Messages / Confirmations) | clic chacune | naviguent (RDV→Agenda, Salle→Salle d'attente, Messages→Messages, Confirmations→Agenda) ; pas d'affordance visuelle de clic | prat_probe, pb_card_* | OK |
| « Notes du jour » | lecture | empty-state « Aucune consultation aujourd'hui » (30/07 vide) — légit | prat_probe | OK |

### 1.2 Agenda
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| Nav semaine ‹ / › | (vue) | bandeau « 27 juil. – 2 août 2026 » | prat_agenda | OK |
| « Filtrer par date » | (vue) | filtre présent | prat_agenda | OK |
| Cartes RDV (heure, patient, motif) | lecture | statuts clairs : **Terminé** (bleu), **À confirmer** (ambre) | prat_agenda | OK |
| Bouton « Confirmer » (RDV à confirmer) | (présent) | confirme un RDV — testé côté secrétariat (#4535 sur conflit) | prat_agenda | OK |

### 1.3 Patients
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| « Rechercher un patient » | champ | recherche présente | prat_patients | OK |
| Lignes patients | tap | ouvre la fiche (`/patients/{id}`) | prat_patients / prat_fiche_marc | OK |
| **Lignes avatar « ? » sans nom (×2)** | lecture | **ligne vide, nom manquant non géré** | prat_patients | **BUG #4542** |

### 1.4 Fiche patient (Marc Dubois)
Sections (scroll) : Header (naissance, tél, solde, lapins) → Historique RDV (statuts
Demandé/Honoré/Annulé) → **Étiquettes** ([Ajouter], « Aucune étiquette ») → **Documents**
([Envoyer un document] + chips filtres : Tous/Devis/Facture/Ordonnance/Radio/CBCT/Photo/
Compte-rendu/Consigne/Attestation/Carte mutuelle/**Passeport implantaire**/Consentement) →
**Notes** ([Enregistrer les notes]) → actions bas.
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| [Enregistrer les notes] | (présent) | sauvegarde la note praticien | prat_fm_4 | OK (présent) |
| [Schéma dentaire] | clic | → odontogramme `/patients/{id}/dental-chart` | prat_dental | OK |
| [Bilan parodontal] | clic | → `/patients/{id}/periodontal-chart` | prat_fm_4 | OK (nav) |
| [Plan de traitement] | clic | → `/patients/{id}/treatment-plans` | prat_plan | OK |
| [Exporter PDF] | clic | action déclenchée, **aucun 4xx** (download non vérifiable en headless) | prat_exportpdf | OK |
| Documents : chips filtres + [Envoyer un document] | (présents) | filtre par catégorie ; upload document | prat_fm_2 | OK (présents) |
| **⚠ Aucun bouton « Créer une ordonnance »/« Prescrire »** | recherche exhaustive | **impasse** : le tab Ordonnances renvoie ici mais la fiche n'offre aucune entrée ordonnance | prat_ordo, prat_exportpdf | **BUG #4541** |

### 1.5 Schéma dentaire (odontogramme) — inclut les implants (#4141 partiel)
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| Toggle Adulte/Enfant | (présent) | bascule denture | prat_dental | OK |
| Grille dents FDI (18→28, 48→38) | tap dent | sélectionne la dent | prat_dental | OK |
| Légende états (Sain…**Implant**…Fracturée) | choix état | applique l'état ; **dent 26 → Implant (teal)** | prat_dental_save | OK |
| [Enregistrer] | clic | **sauvegarde ; persiste après reload** (dent 26 toujours Implant) ; aucun 4xx | prat_dental_recheck | OK |

### 1.6 Consultation (séances) + saisie acte CCAM (#4120 amont, #3402/#4048)
Liste séances filtrable (En cours / Terminée / Annulée). Ouvrir une séance « En cours ».
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| Filtre En cours/Terminée/Annulée | (présent) | segmenté statut | prat_consult | OK |
| Séance « En cours » | tap | détail : header total, Note de séance, Choisir une dent, Favoris, recherche CCAM, [Terminer] | prat_seance | OK |
| « Rechercher un acte CCAM » | taper « obturation » | suggestions (HBJD001/002/003…), **200** | prat_ccam_search | OK |
| Suggestion CCAM | tap | ouvre éditeur : **Numéro de dent** + **Montant** (pré-rempli tarif réf. 45,29 €) | prat_ccam_editor | OK |
| Éditeur : dent=26 + [Ajouter] | remplir+soumettre | acte ajouté : **1 acte·23,00 € → 2 actes·68,29 €** ; ligne « HBJD003 · Dent 26 · 45,29 € » ; aucun 4xx | prat_ccam_added2 | OK |
| [Terminer] (clôture séance) | (présent) | clôture la séance | prat_seance | OK (présent) |
| Note de séance ([Modèle], [Enregistrer la note]) | (présents) | saisie/sauvegarde note | prat_seance | OK (présents) |

### 1.7 Plans de traitement / phases (#4120)
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| Liste plans (titre + statut draft/done) | lecture | plans « QA-… », phases « 1. Phase X » statut requested/done | prat_plan | OK |
| Ligne phase | tap | **aucun effet** (phases non cliquables, pas de détail) | prat_phasedetail | OK (mais voir décompte) |
| [Ajouter une phase] | clic | dialog « Nouvelle phase » : **champ Titre uniquement** ([Annuler]/[Créer]) | prat_phaseform | OK |
| **Décompte séances par phase** | recherche | **non affiché** (X/Y absent partout) → #4120 non vérifiable en UI | prat_plan | note #4120 |
| [Nouveau plan de traitement] / FAB + | (présents) | création plan | prat_plan | OK (présents) |

### 1.8 Ordonnances
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| Onglet Ordonnances | ouvrir | empty « Aucune ordonnance en cours — Ouvrez une fiche patient… » **sans bouton** | prat_ordo | **BUG #4541** |
| (bouton Renouveler #4132) | recherche | **absent** (backlog #4132 ouvert) — attendu | — | n/a (backlog) |

### 1.9 Devis (#4072/#4163 échéancier = patient-side, absent ici)
| Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|
| Liste devis (Reste à charge + statut Brouillon/Signé/Envoyé + date) | lecture | claire, statuts colorés | prat_devis | OK |
| Devis (Brouillon) | tap | détail : Total plan, Reste à charge, Plan de soins (Phase 1 · actes + montants), mention eIDAS | prat_devis_detail | OK |
| **[Envoyer au patient]** | clic | **écran succès « Devis envoyé — transmis à Marc Dubois pour signature »** ; aucun 4xx | prat_devis_sent | OK |
| [Retour à la liste] | (présent) | retour liste | prat_devis_detail | OK |
| Échéancier de paiement (Alma) | recherche | **absent** de l'UI praticien (backlog #4072/#4163) — attendu | — | n/a (backlog) |

### 1.10 Tabs annexes (Salle d'attente / Stock / Inventaire / Labo / Messages / Messagerie interne / Démo A2UI)
| Écran | Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|---|
| Salle d'attente | [Actualiser], « Appeler suivant » | clic | refresh 0 patient ; « Appeler suivant » **désactivé** (0 patient) — correct | pb_salle2 | OK |
| Stock | FAB « Nouvelle demande » → pharmacie + article + qté + [Envoyer] | remplir+soumettre | recherche pharma **200** ; **`201 POST /v1/cabinet/stock-requests`** ; item « Envoyée » en tête | pb_stock_submitted | OK |
| Stock | ligne de liste | tap | aucun effet (read-only) — acceptable | — | OK |
| Inventaire | « Mouvement » (item) → Type/Qté + [Valider] | soumettre | **`201 POST /v1/cabinet/stock-items/{id}/movements`** ; Gants 5→7 | pb_inv_done | OK |
| Labo | « Avancer » (kanban statut) | clic | **`200 PATCH /v1/cabinet/lab-work-orders/{id}`** ; item change de colonne | pb_labo_adv | OK |
| Messages | conversation → « Votre message… » + Entrée | envoyer | **`201 POST /v1/cabinet/conversations/{id}/messages`** ; bulle apparaît | pb_msg_sent | OK |
| Messages | « Créer un RDV » (en-tête conv) | clic | **dialog « Aucun créneau disponible » sans date-picker ni recours** ; Créer mort ; 0 requête | pb_msg_rdv_2 | **BUG #4540** |
| Messagerie interne | « Écrire à l'équipe » + Entrée | envoyer | **`201 POST /v1/cabinet/messages`** ; Entrée **fonctionne** (≠ secrétariat #4538) | pb_interne_sent | OK |
| **Démo A2UI** | ouvrir + « Prendre rendez-vous » | clic | écran « A2UI · démo locale » ; CTA → snackbar « Action A2UI : demo.cta », **0 requête/0 nav** — **artefact dev** | pb_a2ui_0, pb_a2ui_btn_1 | **BUG #4539** |

### Verdicts humains — praticien
- **Dashboard** util 4.5/5, esth 4/5 — clair, cartes cliquables pertinentes ; manque l'affordance de clic.
- **Agenda** util 4/5, esth 4/5 — statuts colorés lisibles, actions Confirmer visibles.
- **Patients / Fiche** util 4/5, esth 4/5 — fiche riche et pro ; gâchée par l'absence d'entrée « ordonnance » (#4541) et les lignes « ? » (#4542). Jargon « Lapins » (= no-shows) peu explicite ; solde négatif non formaté = donnée QA.
- **Consultation (CCAM)** util 4.5/5, esth 4.5/5 — **le point fort** : recherche CCAM + éditeur dent/montant pré-rempli + total recalculé = fluide et correct.
- **Schéma dentaire** util 4/5, esth 4/5 — odontogramme FDI propre, sauvegarde qui persiste.
- **Plans de traitement** util 3/5, esth 4/5 — phases lisibles mais **pas de décompte de séances** ni de détail au tap (#4120 invisible).
- **Devis** util 4.5/5, esth 4.5/5 — détail clair + envoi avec **écran de succès** (mieux que le patient #4534).
- **Stock/Inventaire/Labo** util 4.5/5, esth 4.5/5 — workflows complets qui aboutissent (201/200). Labo (kanban) parmi les plus aboutis.
- **Messages / Messagerie interne** util 4/5, esth 4.5/5 — envoi OK ; « Créer un RDV » cassé (#4540).
- **Démo A2UI** util 1/5, esth 2/5 — n'a rien à faire en prod (#4539).

---

## 2. PATIENT — https://patient.doc.nubia-link.com
Compte : `marc.dubois@patient.test`. **Nav = barre du bas** (Rechercher / Mes RDV / Messages /
Documents / Profil).

### 2.1 Recherche / carte (parcours « je veux un RDV »)
| Écran | Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|---|
| Home `/` | Barre recherche | « dentiste teleconsultation » + Enter | chip NLP « ✨ Chirurgien-dentiste en téléconsultation », liste filtrée 13 | pt_searchbar | OK |
| Home | Chip « Dentiste » | clic | 17→13 praticiens, chip vert, pins carte MAJ | pt_filter_dentiste | OK |
| Home | Carte (map) + clusters | rendu | lisible, pins praticiens, recentrage au tap | pt_home | OK |
| Home | Carte praticien (liste) | clic « Dr Amélie Dubois » | bottom-sheet fiche + CTA « Voir les créneaux » | pt_fiche | OK |

### 2.2 Booking (le test critique — historiquement cassé) → **PASSE**
| Écran | Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|---|
| Fiche | « Voir les créneaux » | clic | écran créneaux par jour (Matin/Après-midi) | pt_creneaux | OK |
| Créneaux | SlotChip 09:00 | clic | chip vert, champ « Motif » apparaît, CTA grisé | pt_motif | OK |
| Motif | champ « Motif » | taper | CTA « Confirmer le rendez-vous » s'active | pt_motif_filled | OK |
| Motif | **« Confirmer le rendez-vous »** | clic | `POST /slots/{id}/hold` 200 ; **`POST /v1/bookings` 201** (status requested) ; snackbar « Demande envoyée » ; **retour accueil (pas d'écran récap)** | pt_confirmed | OK booking / **BUG ux #4534** |
| Mes RDV | onglet + carte RDV | vérif | nouveau RDV présent « Contrôle annuel · Lun 3 aoû 09:00 · En attente » | pt_mesrdv | OK |
| Mes RDV | **« Modifier »** → SlotChip proche + « Confirmer la modification » | clic | **`PATCH /v1/appointments/{id}` 409 `too_late`** + snackbar générique ; créneau lointain → PATCH 200 (contrôle) | pt_modifier, pt_modify_done | **BUG #4532** |
| Mes RDV | « Annuler » | clic | dialog « Annuler ce RDV ? … irréversible » (Annuler/Confirmer) | pt_annuler_dialog | OK (dialog) |
| — | `GET /v1/me` (auto) | — | **401 → éjection /#/login**, aucun appel de refresh (refresh_token inutilisé) | pt_session_check | **BUG #4533** |

### 2.3 Devis / Messages / Documents / Profil
> _(rempli par le run de complétion — voir §2.4 ci-dessous)_

### Verdicts humains — patient
- **Home/carte** util 4/5, esth 4.5/5 — très « Doctolib », recherche NLP avec interprétation = excellent.
- **Créneaux/Motif/Confirmation** util 4/5, esth 4/5 — logique CTA correcte ; **manque l'écran de récap** final (#4534).
- **Mes RDV** util 4/5, esth 4/5 — cartes claires ; **Modifier** propose des créneaux qu'il refuse (#4532).
- **Login** util 4/5, esth 4/5 — minimal, propre.

---

## 3. SECRÉTARIAT — https://secretariat.doc.nubia-link.com
Compte : `sonia.accueil@cabinet-lyon.test`. **12 onglets** : Tableau de bord, Salle d'attente,
Liste d'attente, Agenda, Créneaux, Patients, Devis, Stock, Messages, Motifs de RDV,
Secrétariats, Statistiques (+ Messagerie interne, Déconnexion).
**Cloisonnement : PASS** — aucun contenu clinique (actes/ordonnances/notes) visible.
**#4128 bordereau de remise en banque : NON exposé dans l'UI** = feature backend backlog (#4128 ouverte), **PAS un bug**.

| Écran | Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|---|
| Dashboard | 3 tuiles (7/26/1) | lecture | chiffres cohérents | sec_dash | OK |
| Dashboard | cartes « Prochains RDV »/« À traiter » | clic | non cliquables (info) | sec_dash | OK |
| Dashboard | (fond) | chargement | `403 GET /v1/cabinet/members` + `/audit-log` (RBAC attendu) | — | OK |
| Salle d'attente | liste | vue | « Salle d'attente vide » (légit) | sec_salle | OK |
| Liste d'attente | **[Combler]** | clic | **`409 POST /cabinet/waiting-list/:id/offer`** → **erreur plein écran, liste masquée** | sec_combler | **BUG #4536** |
| Agenda | **[Confirmer]** (RDV en conflit) | clic | **`409 POST /cabinet/appointments/:id/confirm`**, **aucun feedback** | sec_confirm409 | **BUG #4535** |
| Agenda | [Confirmer] (non conflictuel) | clic | passe « Confirmé » (OK) | sec_confirm_snack | OK |
| Agenda | [+ Nouveau RDV] → Créneau+Patient+[Créer] | remplir+soumettre | **RDV créé** (« cette semaine » 37→38), pas de 4xx | sec_rdv_result | OK |
| Créneaux | filtres Praticien/date | vue | 200 créneaux groupés | sec_creneaux | OK |
| Patients | recherche + liste + fiche | clic | fiche admin (naissance, solde, lapins, docs=factures) ; 1 patient nom « – » | sec_patient_detail | OK (cosm.) |
| Patients | [Nouveau patient] → [Créer le dossier] | champs vides | bouton **désactivé** tant que requis vides (validation) | sec_newpatient | OK |
| Devis | liste + détail (brouillon/signé) | clic | **lecture seule — aucune action créer/envoyer** | sec_devis_brouillon | **BUG #4537** |
| Stock | [Nouvelle demande] → form | ouvrir | form pharmacie+article+qté+[Envoyer] | sec_stock_new | OK |
| Messages | conversation → composer | envoyer | **message envoyé** (apparaît, pas de 4xx) ; bouton « Créer un RDV » présent | sec_msg_sent | OK |
| Motifs de RDV | liste | vue | « Aucun motif enregistré » (empty, pas de bouton créer) | sec_motifs | OK (empty) |
| Secrétariats | liste A/B « Actif » | vue | lecture seule (cohérent members 403) | sec_secretariats | OK |
| Statistiques | KPIs pilotage | vue | CA 3390€, transfo 86%, devis 107/125, actes/praticien | sec_stats | OK |
| Messagerie interne | composer + **Entrée** | envoyer | **Entrée n'envoie pas** ; l'icône envoyer marche | sec_msginterne_send | **BUG #4538** |

### Verdicts humains — secrétariat
- **Dashboard** util 4/5, esth 4/5 — clair ; cartes non cliquables = occasion manquée.
- **Liste d'attente** util 3/5, esth 4/5 — l'unique action « Combler » est cassée (#4536) → inexploitable.
- **Agenda** util 4/5, esth 4/5 — bon rendu ; « Confirmer » sans feedback en conflit (#4535).
- **Patients/Créneaux/Stock/Messages** util 4/5, esth 4/5 — solides, workflows aboutis.
- **Devis** util 2/5, esth 4/5 — beau mais **cul-de-sac** lecture seule (#4537).
- **Motifs de RDV** util 2/5 — écran vide sans action.
- **Statistiques/Secrétariats** util 3.5/5, esth 4/5 — pilotage lisible, read-only cohérent RBAC.

---

## 4. PHARMACIE — https://pharmacie.doc.nubia-link.com — **BLOQUÉE**
Compte : `jean.officine@pharmacie-lyon.test` (creds **valides** : `POST /v1/auth/login` = **200**
en direct API ; `GET /v1/me` = 200 ; `GET /v1/pharmacy/orders` = 200 avec commandes réelles).
**MAIS l'app est 100% inaccessible** : après login, `POST /v1/auth/select-pharmacy-context`
renvoie **403 `forbidden`** malgré la session valide → **rebond permanent vers `/login`**.
Aucun écran métier (dashboard, commandes, préparation, stock, messagerie) atteignable.
→ **BUG bloquant #4531**. Le §9 exhaustif est **impossible** tant que #4531 n'est pas corrigé.

| Écran | Élément | Action | Effet | Screenshot | OK/BUG |
|---|---|---|---|---|---|
| boot → /login | (chargement, session valide) | ouvrir | `GET /v1/me` 200 → `POST /v1/auth/select-pharmacy-context` **403** → /login | ph_dashboard | **BUG #4531** |
| /login | E-mail pro / Mot de passe / Se connecter | (rendu) | écran propre « Espace pharmacie » | pharma_login | OK (rendu) |
| dashboard/commandes/préparation/stock/messagerie | — | — | **non atteignables** (conséquence #4531) | — | BLOQUÉ |

### Verdict humain — pharmacie
- **Login « Espace pharmacie »** util 3/5, esth 3.5/5 — propre mais éjection **silencieuse** (aucun
  message n'explique le rejet ; un pharmacien légitime croit à un mauvais mot de passe).
- **Reste de l'app** : **non évaluable** (#4531). Adoption = 0 tant que non corrigé.
</content>
