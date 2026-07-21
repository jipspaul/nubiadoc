# E2E Scenarios — Validation production cross-rôles

> Source de vérité des scénarios end-to-end multi-rôles que la suite Playwright
> doit faire passer pour qu'on considère le produit "prêt prod". À iterer
> au fil des features.
>
> Diffère du QA "smoke check" (navigation + canvas/console) : ici on **utilise
> vraiment l'app** (login, click, fill, submit) et on **vérifie que l'action
> d'un rôle se reflète chez les autres**.

---

## Pourquoi ce doc

Le QA smoke actuel charge une URL, regarde le canvas, compte les console.error.
Il dit "ça affiche" mais **pas "ça marche"**. Une page peut rendre OK et :

- crasher au submit du form
- ne pas persister les données (refresh = perte)
- ne pas propager côté secrétariat ce que le patient a fait
- laisser un patient B accéder aux données du patient A (RLS cassée)
- ne pas notifier le praticien quand le wedge passe en "signed"

Ces scénarios listent ce qu'il faut prouver avant de pouvoir dire "production".

## Légende

- **P** = Patient (app_patient) · **S** = Secrétariat (app_secretariat) · **D** = Praticien (app_practicien)
- **🔴 P0** = bloquant prod si KO · **🟠 P1** = dégrade fortement · **🟡 P2** = à fixer
- **WS** = canal WebSocket impliqué (cf. `docs/12-api-reference.md` §20)

---

## A. Cœur transactionnel (P0)

### A1 — Booking + confirmation patient/secrétariat

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | Login `patient.doc.nubia-link.com` | dashboard chargé |
| 2 | P | `/appointments` → choisit praticien + créneau + motif → submit | `POST /v1/appointments` 201, `appointment_id` retourné |
| 3 | S | Login `secretariat.doc.nubia-link.com` | dashboard chargé |
| 4 | S | `/agenda` jour du RDV | event `appointment_id` visible (status `requested`) |
| 5 | S | Click event → "Confirmer" | `POST /v1/cabinet/appointments/:id/confirm` 200, status passe `confirmed` |
| 6 | P | Refresh `/mes-rdv` | RDV en statut "Confirmé" + notif affichée |

**Invariant** : no double-booking sur même créneau (contrainte EXCLUDE PostgreSQL).

### A2 — Annulation patient (within window)

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1-2 | (préreq A1 step 1-2, RDV `confirmed`) | | |
| 3 | P | `/mes-rdv` → click RDV → "Annuler" + raison | `POST /v1/appointments/:id/cancel` 200 |
| 4 | S | `/agenda` (WS push agenda) | event marqué `cancelled` en ≤2s sans refresh |
| 5 | Backend | check audit log | row dans `audit_log` avec `event=appointment_cancelled, actor=P` |

**Invariant** : annulation hors fenêtre → 409 `too_late` (test séparé A2bis).

### A3 — Modification créneau côté secrétariat (reschedule)

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | S | `/agenda` → drag-drop event vers autre créneau | `PATCH /v1/cabinet/appointments/:id` 200 |
| 2 | P | `/mes-rdv` (WS push) | nouveau créneau affiché en ≤2s, notif "RDV déplacé" |

### A4 — Waiting room temps réel (P→S→D→P)

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | `/checkin` jour J | `POST /v1/appointments/:id/checkin` 200 |
| 2 | S | `/salle-attente` (WS channel `waiting_room`) | patient apparaît dans la queue en ≤2s |
| 3 | D | `/waiting-room` → "Appeler suivant" | `POST /v1/cabinet/waiting-room/call-next` 200, patient `status=called` |
| 4 | P | UI patient | reçoit notif "C'est à vous" (WS `patient_queue:{appointment_id}` event `your_turn`) en ≤2s |

**Invariant WS** : seuls les pros du même `cabinet_id` voient le canal (test isolation A4bis).

---

## B. Wedge (parcours monétisable) (P0)

### B1 — Devis → signature → paiement

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | D | `/devis` → crée devis (items, deposit_pct) | `POST /v1/cabinet/quotes` 201, `quote_id` |
| 2 | P | `/financial` | devis "en attente signature" visible |
| 3 | P | Click devis → "Signer" → flux Yousign | `POST /v1/quotes/:id/sign` 200, redirection Yousign |
| 4 | Backend | webhook Yousign `signature.completed` | `POST /v1/webhooks/yousign` 200, quote `status=signed`, `signed_at` set |
| 5 | P | Click "Payer acompte" → flux Stripe | `POST /v1/payments/intent` 200 |
| 6 | Backend | webhook Stripe `payment.succeeded` | `POST /v1/webhooks/stripe` 200, payment `status=paid` |
| 7 | D | `/devis/:id` refresh | devis "Signé + Payé", date+SHA signature affichées |

**Invariants** :
- impossible re-modifier le devis après `signed_at` (409 `quote_locked`)
- payment idempotent (webhook reçu 2× → un seul paiement)

### B2 — Modification devis avant signature

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | (préreq B1 step 1, quote non signée) | | |
| 2 | S | `/devis/:id` → modifie items → save | `PATCH /v1/cabinet/quotes/:id` 200 |
| 3 | P | `/financial` (refresh OU WS) | nouveau montant + alerte "devis mis à jour" |
| 4 | P | signe → check Yousign | doc signé porte le NOUVEAU montant |

### B3 — Refus signature

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | (préreq B1 step 1-3) | | |
| 2 | P | Sur page Yousign → "Refuser" | retour app, quote `status=pending` (pas `signed`, pas `cancelled`) |
| 3 | S | relance possible : `POST /v1/cabinet/quotes/:id/remind` 200 | notif renvoyée |

---

## C. Cloisonnement clinique + RLS (P0, conformité)

### C1 — Secrétariat NE peut PAS accéder au clinique

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | S | tente `GET /v1/cabinet/patients/:id/notes` (Postman OU URL navigateur direct) | **403 Forbidden** |
| 2 | S | tente `GET /v1/cabinet/consultations/:id` | **403** |
| 3 | S | UI `/patients/:id` | onglet "Notes cliniques" absent (pas seulement disabled — pas dans le DOM) |

**Invariant** : la conformité audit (`docs/07`) interdit toute fuite clinique au secrétariat.

### C2 — RLS multi-patient

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P1 | login + book RDV → `appointment_id=X` | OK |
| 2 | P2 | login séparé → `GET /v1/appointments` | response NE contient PAS appointment X |
| 3 | P2 | tente `GET /v1/appointments/X` direct | **404 Not Found** (pas 403, pour éviter info leak sur l'existence) |
| 4 | P2 | tente `GET /v1/documents` | aucun doc de P1 visible |

### C3 — Multi-cabinet via account_guardianship

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P-titulaire | ajoute proche (enfant) → `POST /v1/account/guardians` | child `account_id` créé |
| 2 | P-titulaire | book RDV "pour enfant" | RDV créé avec `patient_account_id=child` |
| 3 | S du cabinet | `/agenda` | event affiche identité ENFANT + mention "représenté par titulaire" |
| 4 | Backend | audit | log mentionne `actor=titulaire, target_patient=child, link=guardianship` |

---

## D. Documents + Messagerie (P1)

### D1 — Upload doc patient → vu par praticien

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | `/documents` → upload PDF | `POST /v1/documents` 201, doc visible dans liste |
| 2 | P | refresh page | doc toujours là (persistance) |
| 3 | D | `/patients/:id/dossier` | doc présent + métadonnées (date, taille, category) |
| 4 | D | click → download | PDF identique à celui uploadé (checksum) |

### D2 — Ordonnance signée

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | D | `/ordonnances` → nouvelle ordonnance + items | `POST /v1/cabinet/prescriptions` 201 |
| 2 | D | click "Signer" → flux Yousign | `POST /v1/cabinet/prescriptions/:id/sign` 200 |
| 3 | Backend | webhook Yousign | prescription `signed_at` set |
| 4 | P | `/documents` | ordonnance présente, catégorie `ordonnance`, télécharge OK avec signature attachée |

### D3 — Messagerie cabinet temps réel

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | `/messaging` → ouvre conversation cabinet → envoie message | `POST /v1/conversations/:id/messages` 201 |
| 2 | S | `/cabinet_messaging` (WS `conversation:{id}` event `message_created`) | message visible en ≤2s sans refresh |
| 3 | S | répond | `POST /v1/cabinet/conversations/:id/messages` 201 |
| 4 | P | UI patient | nouveau message visible en ≤2s |
| 5 | S | marque lu | event `read` propagé, P voit double-coche |

---

## E. Robustesse production (P1)

### E1 — Refresh mid-flow

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | remplit form RDV (3 champs) | data en `localStorage` (draft) |
| 2 | P | F5 navigateur | form pré-rempli OU bannière "brouillon récupéré" |

### E2 — Token expiry mid-action (BUG-1 regression)

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | login | tokens stockés |
| 2 | Backend | invalide token côté serveur OU attend expiry | |
| 3 | P | déclenche 3 requêtes concurrentes (ex. dashboard avec widgets parallèles) | les 3 réussissent (refresh queue applique BUG-1 fix) |

### E3 — Auth path forcing

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P (non logué) | URL directe `/cabinet/agenda` | redirection `/login` (pas de leak via deep-link) |
| 2 | P (logué) | URL directe `praticien.doc.nubia-link.com` | refus / redirection (rôle mismatch) |

### E4 — Offline → online resync

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | offline navigateur (DevTools) | bannière "hors ligne" |
| 2 | P | tente submit form | erreur claire, données conservées |
| 3 | P | online | bannière disparaît, submit possible OU draft restauré |

---

## F. Marketplace cross-cabinet (P1, post-MVP)

### F1 — Search providers + book cross-cabinet

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | P | `/search?q=ostéo Lyon` | résultats providers d'autres cabinets |
| 2 | P | sélectionne créneau → `POST /v1/slots/:id/hold` | hold_token valide 5min |
| 3 | P | `POST /v1/bookings` avec hold_token | appointment créé chez le BON cabinet (pas chez le cabinet d'origine de P) |
| 4 | S du cabinet TARGET | `/agenda` | event visible (mais identité patient minimisée si premier RDV) |

---

## G. Parcours clinique dentaire (P0)

> Le métier réel du produit (dentaire), pas l'infra transactionnelle générique
> (A-F couvrent RDV/paiement/messagerie mais aucun scénario ne joue le cœur
> clinique). Ajouté 2026-07-22 après un audit du référentiel fonctionnel
> Veasy/Desmos qui a fait remonter ~136 gaps sur le domaine dentaire (schéma
> dentaire, actes CCAM, plan de traitement) — G1/G2 valident bout-en-bout ce
> qui vient d'être livré côté API + Flutter pour ce domaine.

### G1 — Consultation dentaire complète → devis patient

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | D | Login `praticien.doc.nubia-link.com` | dashboard chargé |
| 2 | D | `/patients/:id` → ouvre le schéma dentaire (odontogramme) | notation FDI affichée, `GET /v1/cabinet/patients/:id/dental-chart` 200 |
| 3 | D | Clique une dent → choisit un état (ex. "à traiter") → enregistre | `PUT /v1/cabinet/patients/:id/dental-chart` 200, la dent change de couleur à l'écran sans refresh |
| 4 | D | Démarre une consultation → recherche un acte CCAM (ex. détartrage) depuis le schéma (dent pré-remplie) → l'ajoute | `POST /v1/cabinet/consultations/:id/acts` 201, `tooth` correspond à la dent cliquée en step 3 |
| 5 | D | Clôture la séance | `POST /v1/cabinet/consultations/:id/complete` 200, un devis est généré (`quote_id` retourné) |
| 6 | D | `/devis/:id` (ou équivalent app_practicien) | devis affiche l'acte CCAM saisi, montant correct, part AMO/AMC si calculée |
| 7 | P | Login patient → écran devis | même devis visible, même montant, même acte |

**Invariant** : le montant du devis correspond exactement à la somme des actes saisis pendant la séance — aucune désynchronisation schéma dentaire ↔ acte ↔ devis.

**Si un maillon manque** (pas d'écran schéma dentaire, pas de route de création de plan, etc.) : ne pas inventer — suivre la règle persona "harnais/écran absent" (issue `[e2e] INFRA-MISSING`), le run continue sur G2 si indépendant.

### G2 — Plan de traitement multi-étapes

| Étape | Acteur | Action | Assert |
|---|---|---|---|
| 1 | D | `/patients/:id` → "Nouveau plan de traitement" | `POST /v1/cabinet/treatment-plans` 201 |
| 2 | D | Ajoute 2 phases, rattache un acte CCAM à chacune | `POST /v1/cabinet/treatment-plans/:id/phases` 201 ×2 |
| 3 | P | Login patient → écran plan de traitement | les 2 phases visibles, actes + statut par phase |
| 4 | D | Marque la phase 1 réalisée | phase 1 passe "réalisée" côté D, et côté P après refresh (ou WS si branché) |

**Invariant** : un plan de traitement sans aucune phase ne doit jamais être facturable — les quote_item se rattachent à une phase existante, pas au plan directement.

---

## Format d'issue E2E

Quand un scénario échoue, l'agent crée :

```markdown
title: [e2e] FAIL — A1 booking-confirmation patient/secretariat (step 4)

## Scénario
A1 — Booking + confirmation cross-rôle
Step 1-3 OK, échec step 4 (Secrétariat ne voit pas le RDV dans /agenda)

## Trace
step 1 [P login]                         OK    1.2s
step 2 [P book RDV /appointments]        OK    2.4s → appointment_id=42
step 3 [S login]                         OK    0.9s
step 4 [S see RDV in /agenda day=today]  ❌    waited 5s, agenda vide

## Évidence
- selector attendu : [data-testid="agenda-event-42"]
- screenshot       : artifacts/a1-step4-agenda-empty.png
- network          : GET /v1/cabinet/appointments?date=2026-06-27 → 200, body=[]
- console errors   : 0
- WS messages reçus : 0 sur channel agenda:{practitioner_id}

## Hypothèses
- (a) Race POST patient ↔ GET cabinet : le RDV n'est pas encore committé en DB ?
- (b) cabinet_id mismatch côté backend ?
- (c) WS agenda channel pas branché côté secrétariat ?

## Bloque scénarios dépendants
A2 (annulation), A3 (reschedule), A4 (waiting room) tous bloqués.
```

Format pour les **PASS** (silencieux — pas d'issue, juste log Matrix `[e2e] A1 PASS 12.3s`).

---

## Stack technique attendue

- **Harness** : Playwright (déjà installé sur `flutter-qa-agent`) + helpers TS dans `front/test/e2e/`
- **Fixtures** : seed déterministe (cabinet + praticien + 2 patients démo) — voir `db/seed/`
- **Credentials** : env `CRED_PATIENT_EMAIL`, `CRED_PATIENT_PASSWORD`, idem `CRED_PRACTICIEN_*`, `CRED_SECRETARIAT_*`
- **Layout** :
  ```
  front/test/e2e/
    fixtures/ (seed-aware helpers : `loginAs(role)`, `bookAppointment()`, etc.)
    scenarios/
      a1-booking-confirmation.spec.ts
      a2-cancellation.spec.ts
      a4-waiting-room-realtime.spec.ts
      b1-wedge-quote-sign-pay.spec.ts
      ...
    e2e.config.ts (Playwright config — timeout 60s/step, 5min/scenario)
  ```
- **Invocation** : `melos run e2e` OU `npx playwright test --project=e2e`
- **Dispatch** : flutter-qa-agent mode `e2e` (voir persona mise à jour)

---

## Priorisation d'implémentation

1. **Infra harness + fixtures** — bloque tout le reste
2. **A1 Booking + confirmation** — flux #1 du produit
3. **A4 Waiting room temps réel** — valide WS end-to-end (livraison récente)
4. **B1 Wedge devis→signature→paiement** — flux monétisable
5. **D3 Messagerie cabinet temps réel** — cross-rôle simple à tester
6. **C1 + C2 Cloisonnement RLS** — conformité (peut être test API direct + screenshot UI)
7. **G1 Consultation dentaire → devis** — cœur métier du produit, valide le lot de fixes dentaire livré 2026-07-22

Le reste (A2, A3, B2, B3, D1, D2, E*, F*, G2) à itérer après que les 6 premiers tournent vert.
