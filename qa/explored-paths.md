# QA Explored Paths

> **Avant d'explorer / d'ouvrir une issue : lire `qa/route-manifest.md`** —
> liste des routes à tester (auth, stratégie d'URL, contenu attendu) et
> **règles anti-faux-positifs**. La plupart des issues fermées venaient de ne
> pas les respecter (route authed testée déconnectée, CSS `::placeholder`,
> mauvaise stratégie hash/path, env déployé en retard sur main).
>
> ⚠️ Le repo documente aussi désormais `qa/human-qa-playbook.md`, une doctrine
> de test "comme un humain" (clic/scroll/jugement visuel, plus de navigation
> par URL) qui **remplace conceptuellement** ce run URL-sweep pour les futurs
> agents QA manuels. Ce run (2026-07-04) a suivi la spec URL-sweep historique
> (v5 streaming) telle que demandée, pas le nouveau playbook — à clarifier
> avec un humain si les deux doctrines doivent converger.

Last run: 2026-07-04T23:51:28.000Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2732 |
| /agenda | secretariat | 2026-07-01 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète (AgendaPage : liste des créneaux, filtre praticien, prise de RDV, confirmation ; câblée dans app_router.dart et ProShell.bodyBuilder), ferme #3172 |
| /notifications | patient | 2026-06-25 | déjà résolu — BlocBuilder exhaustif, try/catch, GetIt enregistré, flutter analyze vert | ferme #2833 |
| /notifications | patient | 2026-07-01 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète (NotificationsPage : états loading/error/empty/loaded, liste, marquage lu, tuiles ; route câblée dans app_router.dart avec BlocProvider > Scaffold > AppBar/body, GetIt enregistré), ferme #3168 |
| /bookable-slots | secretariat | 2026-06-30 | déjà résolu — BookableSlotsBloc wrap try/catch + SafeEmitMixin, BookableSlotsBody (BlocBuilder) couvre tous les states (Initial/Loading/Loaded vide/Loaded/Error via NubiaErrorWidget), route câblée dans app_router.dart (BlocProvider > BookableSlotsPage > Scaffold), bloc enregistré dans GetIt (pro_di.dart), 16 tests bloc+widget verts (bookable_slots_test.dart) | faux positif (frontend) — la régression backend réelle (405 sur GET /v1/cabinet/slots) documentée sous #3055/#3173 est désormais **corrigée** (voir note run 2026-07-04 ci-dessous) |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage, BlocBuilder exhaustif, GetIt, flutter analyze vert | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via location.hash (in-page, sans page.goto) |
| / et /account-setup | patient | 2026-07-01 | méthode C : scan DOM incluait le texte de balises `<style>` injectées (CSS `::placeholder`) via `.textContent` d'un `div` ancêtre | faux positif — ferme #3199 #3201. Fix harness : exclure `style`/`script` du scan DOM + filtre anti-CSS-boilerplate (`::placeholder`, `caret-color`, `-webkit-autofill`) |
| flow C (register praticien) | praticien | 2026-07-01 | déjà résolu — détections 20:25–20:36 antérieures au merge du fix #3194 (21:11, `context.go(cabinetSetup)` sur ProRegisterSuccess dans le listener du BlocConsumer) + follow-ups #3193 (08aac18b) et #3195 (7c4968b0, guestOnlyRoutes anti-course du guard) ; test widget de non-régression ajouté (pro_register_page_test.dart : ProRegisterSuccess → /cabinet-setup) | doublons périmés — ferme #3192 #3196 #3198 (le bug de fond récidivait à chaque run jusqu'au 2026-07-02 ; **flow C confirmé OK au run 2026-07-04**, voir note ci-dessous) |
| /messaging, /consultation, /devis, /login, /a2ui-demo | patient, praticien, secretariat | 2026-07-02 | périmé — détections blank-canvas des 29-30/06 (canvasCount:0) antérieures au run complet 2026-07-01T20:47 où TOUTES les routes des 3 apps sont OK ; même famille que #2920-#2935 (artefact harness) | doublons périmés — ferme #3039 #3046 #3056 #3079 #3092 |
| /waiting-room | praticien | 2026-07-02 | périmé — détection navigation du 01/07 (flutterViewPresent:false, pageTitle vide = page pas chargée, transient) ; route OK au run complet 2026-07-01T20:47 | doublon périmé — ferme #3135 |
| /messages | praticien | 2026-07-02 | doublon périmé — #3136 (kind navigation, run 2026-07-01T00:21:57Z, `page.goto: Target page, context or browser has been closed`) déjà documenté faux positif via #3145 (commit 3bfdd0fd, run antérieur 00:00:11Z) : CabinetMessagingBloc try/catch + SafeEmitMixin sur tous les handlers, CabinetMessagingPage switch exhaustif sur le sealed state (7 cas couverts), route wrappée Scaffold dans app_router.dart, bloc + use cases enregistrés GetIt (pro_di.dart, data_registration.dart), flutter analyze vert, 14 tests bloc+widget verts ; crash navigateur/contexte pendant le run, pas une exception app — même famille que #2734/#3135. Le seul finding distinct détecté depuis sur cette route (#3227, console-errors) a suivi son propre traitement, et s'est auto-résolu (voir run 2026-07-04) | doublon périmé — ferme #3136 |
| flow C step 1 | praticien | 2026-07-02 | déjà documenté faux positif usePathUrlStrategy (cf. notes méthodologiques : #3188-#3191 « postés puis fermés ») — #3190 resté ouvert par erreur ; les runs suivants passent l'étape 1 | faux positif — ferme #3190 |
| / (root) | patient | 2026-07-02 | déjà documenté — ligne « ferme #3199 #3201 » du 01/07 (méthode C, CSS ::placeholder) ; l'issue n'avait pas été fermée effectivement | faux positif — ferme #3199 |
| /reviews | patient | 2026-07-02 | même famille méthode C : marker = CSS `flt-text-editing::placeholder` capté dans le DOM, aucun hit grep source ; route OK au run 2026-07-01T20:47 | faux positif — ferme #3167 |
| /pharmacy/orders/:id, /patients/:id (praticien) | patient, praticien | 2026-07-04 | un ID de test factice/non-UUID produit une bannière "Impossible de charger..." attendue (400 côté API, erreur de parsing d'UUID) — comportement correct pour un ID inexistant, pas un bug | non applicable — comportement attendu, pas d'issue filée |
| /admin-membres | secretariat | 2026-07-04 | test avec le compte seed `sonia.accueil` (role=secretary) produit un 403 + bannière "Accès réservé aux administrateurs du cabinet." — gate de permission correctement implémentée, pas un bug | non applicable — comportement attendu, pas d'issue filée |

## Notes méthodologiques harness

- **app_practicien utilise `usePathUrlStrategy()`** (voir `front/apps/app_practicien/lib/bootstrap.dart:11`) — contrairement à patient/secretariat qui routent via `#hash`, praticien utilise des URLs "propres" (pathname). `window.location.hash` y est **toujours vide** ; utiliser `window.location.pathname` + `history.pushState()` + `dispatchEvent(new PopStateEvent('popstate'))` pour naviguer et vérifier la route courante sur cette app. Piège rencontré en Étape 4.5 (Flow C) : deux faux positifs `onboarding-flow-broken` postés puis fermés (#3188, #3189, #3190, #3191) avant correction.
- Formulaire `/register-pro` (praticien) : long formulaire scrollable — le dropdown "Spécialité" et le bouton "Créer mon compte" sont sous le fold à 800px de haut ; scroller `page.mouse.wheel(0, 700)` ×2 (avec `mouse.move` préalable pour cibler le glass pane) avant d'interagir. Faux positifs #3192, #3194, #3195 (jusqu'à interaction correcte).
- Bug réel confirmé (pas un faux positif) : `POST /v1/pro/register` répond 201 mais `ProRegisterPage`/`ProRegisterCubit` ne déclenche aucune navigation post-succès — voir #3198.
- **Run 2026-07-02T07:06 — la course register-pro récidive une nouvelle fois** malgré la fermeture de #3192/#3196/#3198 : POST 201 confirmé, mais le pathname final rebondit sur `/login` au lieu de `/cabinet-setup`. Non re-posté (dup <24h de #3198, fermé 05:49 le même jour) — à surveiller au prochain run une fois la fenêtre anti-doublon expirée si toujours reproduit.
- **Nouvelle classe de bug détectée le 2026-07-02 : bannière d'erreur visible en app malgré 0 console.error et 0 failedRequests** ("Erreur lors du chargement...", DioException probablement avalée par une course sur l'auth-interceptor/token-storage — famille déjà documentée sur #3199/#3167/#3135). Avait touché 8 routes patient (`/`, `/documents`, `/financial`, `/mes-rdv`, `/messaging`, `/notifications`, `/profile`, `/reviews`, issues #3216-#3223) et 2 routes praticien (`/`, `/messages`, issues #3225, #3227). Le harness classe ce cas comme finding même quand les critères mécaniques (whiteRatio/console/requests) indiqueraient un faux OK — toujours lire la capture d'écran. **Toutes ces routes sont revenues à un rendu réel et correct au run 2026-07-04** (contenu réel constaté à l'écran, pas juste critères mécaniques) — classe de bug résolue pour cette vague, mais le pattern lui-même (interceptor/token-storage race) reste à surveiller si il ressurgit.
- Onboarding flow B (secretariat, invitation) : fix confirmé au run 2026-07-02 (PR #3209 / commit `0264b7f5`) — token invalide correctement rejeté (400 `invitation_invalid`), écran "Invitation invalide" affiché. **Reconfirmé OK au run 2026-07-04** (la validation ne se déclenche qu'au submit du formulaire, pas au chargement de la page — le harness doit remplir+soumettre, pas juste naviguer).
- `/bookable-slots` (secretariat) : lacune backend réelle (405 sur `GET /v1/cabinet/slots`) confirmée à nouveau le 2026-07-02. **Corrigée au run 2026-07-04** : `api/src/lib.rs` enregistre désormais `get(scheduling::list_cabinet_slots).post(scheduling::create_cabinet_slot)` — vérifié en direct (grille de créneaux réelle affichée, 0 failed-request). Pas de nouvelle issue filée, régression résolue.
- **Run 2026-07-04T23:51 — Onboarding Flow C (register praticien) est OK pour la première fois après 6+ runs cassés.** Formulaire rempli intégralement (incl. dropdown Spécialité via activation de l'arbre sémantique), `POST /v1/pro/register` → 201, pathname atterrit correctement sur `/cabinet-setup`, formulaire cabinet-setup rendu. La course auth-guard documentée depuis #3192/#3193/#3195/#3196/#3198/#3203/#3204/#3205 ne s'est PAS reproduite ce run. **Une deuxième confirmation indépendante est recommandée avant de considérer la classe de bug définitivement résolue** (l'historique de faux "fix" cosmétiques sur cette route est long).
- **Run 2026-07-04 — nouveau bug bloquant sur Onboarding Flow A (patient signup) : `PATCH /v1/account` rejette systématiquement `birth_date` (422)**, alors que `AccountSetupPage` exige la date de naissance pour activer "Continuer" — bloque 100% des inscriptions patient à l'étape `/account-setup`. Root cause : `front/packages/nubia_data/lib/src/repositories/account_repository_impl.dart:35-37` envoie toujours `birth_date` dans le PATCH, alors que `api/src/auth/mod.rs:2087-2088` renvoie 422 dès que `birth_date` (ou `email`) est présent — cet endpoint est conçu pour ne jamais modifier ces champs. Ceci est un **bug distinct** de l'ancienne course auth-guard (#3100/#3022/#3072/#3025) — celle-ci semble résolue (l'agent atteint bien `/account-setup` sans rebondir sur `/login`), mais le nouveau bug empêche de compléter le flow. Tracké #3384 (P0).
- **Run 2026-07-04 — nouveau bug sur patient `/profile/dependents` : mismatch de nom de champ JSON.** Backend `DependentItem` (`api/src/auth/mod.rs:2957-2963`) sérialise l'id en `dependent_account_id`, mais `DependentDto.fromJson` (`front/packages/nubia_data/lib/src/remote/account/account_dto.dart:74`) lit `json['id']` → `TypeError` avalé en `ParseFailure` générique, bannière "Erreur de décodage de la réponse." malgré 0 console.error / 0 failedRequests (même famille que le bug interceptor déjà documenté, mais cette fois un vrai bug de contrat DTO, pas une course réseau). Tracké #3386 (P1).
- **Nouvelle feature découverte au run 2026-07-04 : "Ma pharmacie" côté patient** (`/pharmacy`, `/pharmacy/search`, `/pharmacy/send`, `/pharmacy/orders`, `/pharmacy/orders/:id`) — jamais explorée avant (absente du registre et du cap précédent), entièrement fonctionnelle, 0 bug, 0 marker feature-gap.
- **Nouvelle route découverte au run 2026-07-04 : praticien `/devis`** (plan de traitement) — absente du registre précédent, entièrement fonctionnelle.
- **Run 2026-07-04 — régression mineure sur praticien `/` : `GET /v1/cabinet/today-notes` → 404**, console.error déclenché, mais le widget concerné se dégrade proprement en état vide (contrairement à la bannière pleine page de l'ancien #3225, désormais résolu). Tracké #3383 (P1), sévérité moindre que l'ancien finding.
- **Run 2026-07-04 — 2 feature-gaps confirmés sur secretariat : `/admin-membres` et `/admin-secretariats`.** Les dialogues d'invitation (`invite_member_dialog.dart`, `invite_secretariat_dialog.dart`) affichent un faux SnackBar de succès ("Invitation envoyée (stub)") sans aucun appel backend réel — stub auto-documenté. Trackés #3381 et #3382 (P3). Distinct des anciens faux positifs CSS #3181/#3182 sur ces mêmes routes.
- **Piège harness confirmé au run 2026-07-04 (patient) : checkbox CGU Flutter.** Un `.click()` DOM brut sur `flt-semantics[role="checkbox"]` ne déclenche pas de vrai événement pointeur — utiliser le `.click()` natif Playwright sur le locator sémantique. Le champ "Date de naissance" est un date-picker Material (dialog), pas un input texte : ouvrir le dialog, basculer en mode "Passer à la saisie" texte, effacer la valeur pré-remplie avant de taper.
- **Piège harness confirmé au run 2026-07-04 (praticien) : contamination de buffer console/réseau entre routes.** Une requête de la route précédente peut se résoudre pendant la fenêtre de capture de la route suivante si le settle-delay après login est trop court, produisant un faux `/devis` en `console-errors` — corrigé en isolant le re-test avec un délai de stabilisation plus long après login.

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3216 (bannière d'erreur disparue, contenu réel affiché) |
| /a2ui-demo | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /account-setup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé isolément ce run ; voir Onboarding flow A pour le parcours complet, qui échoue désormais sur le PATCH /v1/account, pas sur le rendu) |
| /appointments | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /book | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /coverage-setup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /documents | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3217, liste de documents réelle affichée |
| /financial | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3218, liste de devis réelle affichée |
| /forgot-password | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /login | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /mes-rdv | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3219, liste de RDV réelle affichée |
| /messaging | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3220, liste de conversations réelle affichée |
| /notifications | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3221, liste de notifications réelle affichée |
| /oubliettes | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | runtime OK ; feature-gap déjà corrigé — #3224 (non re-testé isolément ce run, hors cap) |
| /pharmacy | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | nouvelle feature "Ma pharmacie", entièrement fonctionnelle |
| /pharmacy/search | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — |
| /pharmacy/send | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — |
| /pharmacy/orders | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — |
| /pharmacy/orders/:id | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | bannière "Impossible de charger" avec un ID factice non-UUID = comportement attendu |
| /profile | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3222 (déjà reconfirmé le 2026-07-03) |
| /profile/dependents | 2026-07-04 | 2026-07-04T23:51:28.000Z | console-errors | bannière "Erreur de décodage de la réponse." — mismatch DTO `id` vs `dependent_account_id` — #3386 |
| /profile/consents | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — |
| /profile/notifications | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /reset-password | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /reviews | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé depuis #3223, état vide légitime "Aucun avis pour ce prestataire." |
| /signup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé isolément ce run ; voir Onboarding flow A) |
| /splash | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-04T23:51:28.000Z | console-errors | corrigé depuis #3225 (bannière pleine page disparue) mais nouvelle régression mineure : GET /v1/cabinet/today-notes → 404, dégradation propre en état vide — #3383 |
| /a2ui-demo | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /agenda | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /cabinet-setup | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /consultation | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | runtime OK ; feature-gap déjà tracké — #3226 |
| /devis | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | nouvelle route (plan de traitement), entièrement fonctionnelle |
| /login | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /messages | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | auto-résolu depuis #3227, liste de conversations réelle affichée |
| /ordonnances | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /ordonnances/new | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /patients | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /patients/test-patient-id | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | bannière "Impossible de charger le patient." avec un ID factice = comportement attendu |
| /register-pro | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | rendu formulaire OK ; flow de soumission complet désormais OK aussi (voir Onboarding flow C — à reconfirmer un run de plus) |
| /splash | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /waiting-room | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | KPI + états vides corrects |
| /a2ui-demo | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /admin-membres | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | runtime OK (403 attendu, rôle secretary) ; feature-gap confirmé — #3381 |
| /admin-secretariats | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | runtime OK ; feature-gap confirmé — #3382 |
| /agenda | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /appointments | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /bookable-slots | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | corrigé — GET /v1/cabinet/slots enregistré côté Rust, grille de créneaux réelle affichée, 0 failed-request |
| /devis | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /devis/test-devis-id | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /liste-attente | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /login | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |
| /messages | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /onboard | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | invitation_token invalide → "Invitation invalide" (reconfirmé, voir Onboarding flow B) |
| /patients | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | cloisonnement clinique respecté (noms seulement, pas de contenu clinique) |
| /salle-attente | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — |
| /splash | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — (non re-testé ce run, hors cap) |

## Onboarding flows (Étape 4.5)

| flow | app | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| A (signup patient) | patient | 2026-07-04T23:51:28.000Z | broken | l'ancienne course auth-guard (#3100) semble résolue (atteint bien /account-setup) mais **nouveau bug bloquant** : PATCH /v1/account rejette birth_date (422), bloque 100% des inscriptions — #3384 (P0) |
| B (invitation secretariat) | secretariat | 2026-07-04T23:51:28.000Z | OK | reconfirmé — fix PR #3209 tient toujours (400 invitation_invalid, "Invitation invalide" affiché) |
| C (register praticien) | praticien | 2026-07-04T23:51:28.000Z | OK | POST 201 → /cabinet-setup atteint avec succès pour la première fois après 6+ runs cassés (#3192/#3193/#3195/#3196/#3198/#3203/#3204/#3205) — à reconfirmer un run de plus avant de considérer la course définitivement résolue |
