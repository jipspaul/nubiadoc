# Plan d'exécution atomique — état après audit (12/06)

> Audit du **code réel** : `git log` + fichiers sur disque + `api/src/lib.rs` (97 routes enregistrées) + `web-console/src/pages/` + `web-console/tests/flows/`.
> **Bilan : 80+ tâches livrées · 3 vraies tâches restantes + dette routes API**.
> Convention : `P#`=`db/`, `R#`=`api/`, `W#`=`web-console/`, `E*`=tests E2E parcours. `[postgre]` `[rust]` `[web]`.
>
> ⚠️ **Lecteur planner** : ce fichier est ta SOURCE DE VÉRITÉ. Tout ce qui est en section A ne doit JAMAIS être re-dispatché. Si tu vois une ligne avec ✅, l'agent va produire un PR vide. Lis bien sections C, D, E qui contiennent le vrai TODO.

---

## A. ✅ Déjà livré — NE PLUS DISPATCHER

### A.1 `[postgre]` (intégral)
- **P1–P9** — table membership, seed comptes/agenda/docs/messagerie/engagement, sanity RLS
- **P10** — table `secretariat` + RLS cabinet-scoped + backfill + seed 2 (commit P10.c #1403 mergé 11/06)
- **P11** — table `secretariat_membership` + RLS + seed
- **P12** — table `provider_secretariat` + seed A→A, B→B
- **P13** — `user_active_memberships()` + GUC `app.current_secretariat_id` + policies scoped
- **P14** — pgTAP isolation secrétariat (831/831 tests verts au 11/06)

### A.2 `[rust]` (régression R1 corrigée + socle complet)
- **R1 ✅ RESTORED (11/06)** — `auth/login.rs` ligne 165 : `SELECT cabinet_id, role, secretariat_id FROM user_all_memberships($1)` → encode `ProRegisterClaims{cabinet_id, role, secretariat_id?}`. Multi-contexte : 1 appartenance → token embarqué ; n appartenances → `ProClaims` nu + `context_required:true`.
- **R2** — refresh porte `cabinet_id+role+secretariat_id` (via `user_all_memberships`)
- **R3** — test `tests/auth_login_pro.rs` présent (PARTIAL : couvre happy path mais pas tous les bords ; voir section D si besoin de durcir)
- **R4** — `POST /v1/cabinet/appointments` (secrétaire crée RDV)
- **R5** — `POST /v1/quotes/:id/sign` (alias `/sign`, voir D.2 pour aligner avec doc12 `/signature`)
- **R6** — `GET /v1/quotes/:id`
- **R7** — `GET /v1/me` multi-contextes
- **R9** — login/refresh multi-contexte (intégré dans R1/R2)
- **R12** — `cabinet_secretariats.rs` CRUD secrétariats + membres
- **R13** — `POST /v1/cabinet/secretariats/:id/staff` provisionner secrétaire

### A.3 `[web]` fondations + auth (intégral)
- **W1–W7** — tokens · session role-aware · api Bearer/401 · endpoints · middleware garde-rôle · kit (10 composants) · AppShell
- **W8–W11** — login+MFA · register+password · onboarding pro · routage par rôle
- **W44** — alignement ports

### A.4 `[web]` Espace patient (intégral)
- **W12** ✅ `patient/accueil` (dashboard agrégé, 186 lignes)
- **W13** ✅ `search`
- **W14** ✅ `patient/rdv/index`
- **W15** ✅ `patient/rdv/[id]/index` (341 lignes, GET/PATCH/cancel/checkin/callback-request)
- **W16** ✅ `patient/rdv/[id]/preparation` (138 lignes)
- **W17** ✅ `patient/rdv/[id]/salle-attente` (97 lignes)
- **W18** ✅ `patient/rdv/reserver` (241 lignes, mergé 11/06 #1442)
- **W19** ✅ `patient/messages`
- **W20** ✅ `patient/documents` index+[id] (166 lignes)
- **W21** ✅ `patient/devis`
- **W22** ✅ `patient/soins`
- **W23** ✅ `patient/profil`
- **W24** ✅ `patient/profil/couverture`
- **W25** ✅ `patient/profil/proches`
- **W26** ✅ `patient/profil/consentements`
- **W27** ✅ `patient/profil/notifications` (409 lignes)

### A.5 `[web]` Espace praticien (intégral)
- **W28** ✅ `praticien/dashboard`
- **W29** ✅ `praticien/agenda`
- **W30** ✅ `praticien/file` salle d'attente (210 lignes)
- **W31** ✅ `praticien/patients` index + [id] (136 + 389 lignes)
- **W32** ✅ `praticien/consultation/[id]` (357 lignes)
- **W33** ✅ `praticien/ordonnances`
- **W34** ✅ `praticien/profil-public`

### A.6 `[web]` Espace secrétaire (intégral)
- **W35** ✅ `secretary/dashboard` (299 lignes)
- **W36** ✅ `secretary/agenda` (400 lignes)
- **W37** ✅ `secretary/liste-attente` (239 lignes)
- **W38** ✅ `secretary/patients`
- **W39** ✅ `secretary/equipe`
- **W40** ✅ `secretary/cabinet`
- **W41** ✅ `secretary/facturation` (195 lignes)
- **W42** ✅ `secretary/messagerie`

### A.7 `[web]` Multi-établissement (partiel)
- **W53** ✅ `auth/select-context` (179 lignes)
- **W54** ✅ `praticien/secretariats` (351 lignes, assignation docteur→secrétariat)
- **W56** ✅ middleware garde contexte (`nubia_ctx` cookie + check dans `middleware.ts`)
- **W57** ✅ `admin/secretariats` index + [id] (374 lignes)

### A.8 `[web]` Finition
- **W43** ✅ `src/pages/test/` supprimé (commit `8c1c78a` via #1315)
- **W45** ✅ `scripts/dev-stack.sh` imprime 3 URLs + 3 comptes démo (mergé 11/06 #1450)
- **W50** ✅ `web-console/README.md` complet 161 lignes (mergé 11/06 #1444)

### A.9 `[web]` E2E tous les parcours (intégral, 21 flows livrés)
- **E0** ✅ `tests/flows/E0.harness.spec.ts` — harnais Playwright multi-rôle + helpers
- **EP1–EP7** ✅ — Onboarding (200L), Recherche→réservation (232L), Gestion RDV+jour J (386L), Messagerie (121L), Documents+devis (277L), Soins+profil (336L), Auth bords (306L)
- **ED1–ED5** ✅ — Dashboard+agenda (191L), Salle d'attente (125L), Patient+consultation (284L), Ordonnance+profil public (173L), Docteur multi-établissement (326L)
- **ES1–ES4 + ES5** ✅ — Agenda (180L), Liste attente+patients (164L), Équipe+cabinet+facturation (154L), Cloisonnement (103L), Secrétaire multi-secrétariat (380L)
- **EX1–EX4** ✅ — Réservation E2E (302L), RDV créé par secrétaire (189L), Wedge devis (259L), Docteur assigne patient-list scoped (350L)

---

## B. ⛔ Régression critique — RIEN

**B.1** R1 a été restauré le 11/06. Plus de régression critique connue. Si une régression apparaît, ajouter une ligne ici avec verdict + correctif AVANT toute autre tâche.

---

## C. ⬜ Vraies tâches web restantes

| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **W52** | sélecteur de contexte (AppShell) | Bouton dans AppShell qui ouvre dropdown des contextes (cabinet × secrétariat) ; click → `POST /v1/auth/select-context` + reload. Affiché seulement si user a >1 contexte (lu via `GET /v1/me`). | R8 (manquant) |
| **W58** | manager — gestion du personnel | Page CRUD pour `{admin,manager}` : créer/inviter secrétaire (`POST /v1/cabinet/secretariats/:id/staff` = R13 ✅), affecter/retirer membre, lister. | R13 ✅, W51 |
| **ES6** | flow E2E manager provisionne secrétaire | `tests/flows/ES6.flow.spec.ts` : manager login → ajoute secrétaire dans secrétariat A → la secrétaire se connecte → voit secrétariat A scoped. | E0 ✅, R13 ✅, W58 |

### Items à confirmer (PARTIAL)
| ID | Tâche | Notes |
|---|---|---|
| **W51** | session contexte | Cookie `nubia_ctx` + parsing dans `middleware.ts` existent ; vérifier qu'il n'y a pas besoin d'une page SSR `/contexts` dédiée. Probablement OK en l'état. |
| **W55** | bandeau contexte sur dashboard secrétaire | Dashboard livré (W35 ✅) mais bandeau « Secrétariat X — Établissement Y » à confirmer présent. Si absent : 1 issue ~30 lignes. |

---

## D. ⬜ Vraies tâches rust restantes

### D.1 R## manquants (multi-contexte)
| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **R8** | `POST /v1/auth/select-context` | Handler dans `api/src/auth/select_context.rs` (fichier déjà créé, vérifier qu'il expose une route. La doc12 §3 dit `{ cabinet_id, secretariat_id? } → JWT scoped`). | P11 ✅, P13 ✅ |
| **R10-complete** | endpoints cabinet secretary-scoped | Filtrage par `secretariat_id` du JWT sur `agenda/patients/waiting-room/appointments/conversations`. Code partiellement présent — auditer chaque handler. | R8 |
| **R11** | `GET/PUT /v1/cabinet/providers/:id/secretariats` | Assignation docteur→secrétariat (admin/manager). Handler à créer dans `provider_secretariat.rs` (fichier existe, vérifier route enregistrée). | P12 ✅ |

### D.2 Cohérence contrat / code
| ID | Tâche | Détail |
|---|---|---|
| **R5-rename** | route signature devis | Doc12 §10 dit `POST /v1/quotes/:id/signature`. Code expose `/sign`. Soit aligner doc, soit ajouter alias. Issue ≤30 lignes. |
| **R3-strict** | bords du test login pro | `tests/auth_login_pro.rs` existe mais cas non couverts : `secretary` filtre conversation `scope=clinical`, pro sans membership renvoie token nu, role `manager`. À durcir si on veut une vraie garde anti-régression. |

---

## E. ⬜ Dette routes API — 45 routes documentées sans handler

> Source : diff `docs/12-api-reference.md` ↔ `api/src/lib.rs` (97 routes en prod, ~140 documentées). Les routes ci-dessous sont **documentées dans le contrat** mais **n'ont pas de handler**.
>
> ⚠️ Note pour le planner : **1 route = 1 issue rust-agent atomique** (handler + 2-3 tests). Vise diff ≤200 lignes.

### E.1 P0 — bloquent E2E patient (8 routes)
1. `POST /v1/appointments` — créer RDV depuis le patient
2. `PATCH /v1/appointments/:id` — modifier
3. `POST /v1/appointments/:id/cancel` — annuler (gère 409 too_late)
4. `POST /v1/appointments/:id/checkin` — check-in jour J
5. `POST /v1/appointments/:id/callback-request` — demande rappel
6. `GET /v1/appointments/:id/preparation` — préparation (bring list dérivée)
7. `GET /v1/appointments/:id/directions?mode=car` — deeplink itinéraire (non stocké)
8. `GET /v1/appointments/:id/queue` — file d'attente (polling, WebSocket plus tard)

### E.2 P0 — bloquent E2E pro (12 routes)
9. `POST /v1/cabinet/members` — inviter membre
10. `PATCH /v1/cabinet/members/:user_id` — modifier rôle
11. `DELETE /v1/cabinet/members/:user_id` — retirer
12. `POST /v1/cabinet/appointments/:id/confirm` — secrétaire confirme RDV
13. `POST /v1/cabinet/appointments/:id/start` — praticien démarre consultation
14. `GET /v1/cabinet/waiting-room` — salle d'attente (polling)
15. `POST /v1/cabinet/waiting-room/call-next` — call-next
16. `GET /v1/cabinet/patients/:id/notes` — journal clinique
17. `POST /v1/cabinet/patients/:id/notes` — créer note (chiffrée, signée)
18. `GET /v1/cabinet/consultations/:id` — détail consultation
19. `POST /v1/cabinet/consultations/:id/acts` — ajouter acte
20. `POST /v1/cabinet/consultations/:id/complete` — finaliser

### E.3 P1 — marketplace (3 routes)
21. `POST /v1/slots/:id/hold` — bloquer slot 5 min + hold_token
22. `POST /v1/bookings` — consomme hold_token, crée appointment + idempotency-key
23. `GET /v1/providers/:id/availability` — créneaux open d'un praticien

### E.4 P1 — webhooks (3 routes)
24. `POST /v1/webhooks/yousign` — signature.completed → quote signed
25. `POST /v1/webhooks/gocardless` — payments.confirmed → payment paid
26. `POST /v1/webhooks/sentry` (déjà spécifié ailleurs ? à confirmer)

### E.5 P1 — devis cabinet (2 routes)
27. `POST /v1/cabinet/quotes` — créer devis (items, deposit_pct)
28. `PATCH /v1/cabinet/quotes/:id` — éditer (409 quote_locked si signé)

### E.6 P2 — messagerie cabinet (2 routes)
29. `GET /v1/cabinet/conversations/:id/messages`
30. `POST /v1/cabinet/conversations/:id/messages`

### E.7 P2 — autres (15 routes restantes)
31. `PATCH /v1/account/coverage` — MAJ couverture (NSS chiffré)
32. `PATCH /v1/account/notification-preferences`
33. `PUT /v1/account/consents/:purpose` — toggle consent
34. `POST /v1/conversations` — créer fil patient
35. `GET /v1/documents` (list)
36. `POST /v1/documents` — upload
37. `GET /v1/documents/:id/download` — URL signée 302
38. `POST /v1/waiting-list` — patient s'inscrit
39. `POST /v1/payments/intent` — Stripe/GoCardless intent
40. `POST /v1/quotes/:id/signature` — démarre flow Yousign (alias /sign)
41. `POST /v1/reviews` (déjà /reviews ? vérifier owner check)
42. `GET /v1/cabinet/search?q=` — annexe A spotlight
43. `POST /v1/cabinet/assistant/ask` — annexe A (post-traction)
44. `GET /v1/ws` — WebSocket (handshake JWT)
45. `POST /v1/pro/verification` — RPPS/ADELI async

---

## F. Definition of Done (mise à jour 12/06)

- **`[postgre]`** : terminé (831/831 pgTAP verts, RLS+migrations OK).
- **`[rust]`** : R1-R7+R9+R12+R13 ✅, manque R8/R10-complete/R11 (~3 issues) + 45 routes contrat E.1-E.7 (priorité P0 d'abord).
- **`[web]` écrans** : terminé (47 pages + 21 flows E2E livrés), manque W52/W58 (~2 issues) + W51/W55 à confirmer.
- **`[web]` finition** : W43, W45, W50 ✅.

## G. Ordre d'attaque conseillé (planner)

> Priorité dispatch (du plus contraint au moins) :

1. **R8 (select-context)** → débloque W52 et test ES5/ES6
2. **R11** + **W58** → débloque ES6
3. **W52** + **W58** (web pur)
4. **ES6** (test E2E)
5. **R10-complete** (durcissement filtrage secretary-scoped)
6. **R5-rename / R3-strict** (cohérence + garde)
7. **Section E P0** (routes API bloquantes — 20 routes)
8. **Section E P1** (marketplace + webhooks — 8 routes)
9. **Section E P2** (le reste — 15 routes)

## H. Notes pour le planner (LIRE AVANT DE GÉNÉRER)

- **Ne JAMAIS dispatcher un item de section A** (=✅). L'agent produira un PR vide. Si tu vois un item là, c'est livré.
- **Avant de créer une issue à partir d'une ligne C/D/E** : `curl -s $FORGEJO/jips/nubiadoc/raw/branch/main/<fichier cible>` pour vérifier que la cible existe / n'existe pas selon le contexte (deletion vs création).
- **1 issue = 1 deliverable testable** : 1 route + 2 tests OU 1 page + check build OU 1 flow + run vert. JAMAIS de "+/et".
- Auto-split rule de l'agent-planner-oc : si tu vois un titre avec "+", "ET", ou ≥2 deliverables → split d'abord.
- Cap planner = **15 issues max par run** (cluster mono-nœud, voir POSTMORTEM-2026-06-03).
