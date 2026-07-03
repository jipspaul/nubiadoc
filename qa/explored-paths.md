# QA Explored Paths

> **Avant d'explorer / d'ouvrir une issue : lire `qa/route-manifest.md`** —
> liste des routes à tester (auth, stratégie d'URL, contenu attendu) et
> **règles anti-faux-positifs**. La plupart des issues fermées venaient de ne
> pas les respecter (route authed testée déconnectée, CSS `::placeholder`,
> mauvaise stratégie hash/path, env déployé en retard sur main).


Last run: 2026-07-02T07:06:22.000Z

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
| /bookable-slots | secretariat | 2026-06-30 | déjà résolu — BookableSlotsBloc wrap try/catch + SafeEmitMixin, BookableSlotsBody (BlocBuilder) couvre tous les states (Initial/Loading/Loaded vide/Loaded/Error via NubiaErrorWidget), route câblée dans app_router.dart (BlocProvider > BookableSlotsPage > Scaffold), bloc enregistré dans GetIt (pro_di.dart), 16 tests bloc+widget verts (bookable_slots_test.dart) | faux positif (frontend) — mais voir régression backend réelle #3055 confirmée à nouveau le 2026-07-02 (405 sur GET /v1/cabinet/slots, route jamais enregistrée côté Rust) |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage, BlocBuilder exhaustif, GetIt, flutter analyze vert | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via location.hash (in-page, sans page.goto) |
| / et /account-setup | patient | 2026-07-01 | méthode C : scan DOM incluait le texte de balises `<style>` injectées (CSS `::placeholder`) via `.textContent` d'un `div` ancêtre | faux positif — ferme #3199 #3201. Fix harness : exclure `style`/`script` du scan DOM + filtre anti-CSS-boilerplate (`::placeholder`, `caret-color`, `-webkit-autofill`) |
| flow C (register praticien) | praticien | 2026-07-01 | déjà résolu — détections 20:25–20:36 antérieures au merge du fix #3194 (21:11, `context.go(cabinetSetup)` sur ProRegisterSuccess dans le listener du BlocConsumer) + follow-ups #3193 (08aac18b) et #3195 (7c4968b0, guestOnlyRoutes anti-course du guard) ; test widget de non-régression ajouté (pro_register_page_test.dart : ProRegisterSuccess → /cabinet-setup) | doublons périmés — ferme #3192 #3196 #3198 (⚠️ mais le bug de fond récidive, voir note run 2026-07-02 ci-dessous) |
| /messaging, /consultation, /devis, /login, /a2ui-demo | patient, praticien, secretariat | 2026-07-02 | périmé — détections blank-canvas des 29-30/06 (canvasCount:0) antérieures au run complet 2026-07-01T20:47 où TOUTES les routes des 3 apps sont OK ; même famille que #2920-#2935 (artefact harness) | doublons périmés — ferme #3039 #3046 #3056 #3079 #3092 |
| /waiting-room | praticien | 2026-07-02 | périmé — détection navigation du 01/07 (flutterViewPresent:false, pageTitle vide = page pas chargée, transient) ; route OK au run complet 2026-07-01T20:47 | doublon périmé — ferme #3135 |
| /messages | praticien | 2026-07-02 | doublon périmé — #3136 (kind navigation, run 2026-07-01T00:21:57Z, `page.goto: Target page, context or browser has been closed`) déjà documenté faux positif via #3145 (commit 3bfdd0fd, run antérieur 00:00:11Z) : CabinetMessagingBloc try/catch + SafeEmitMixin sur tous les handlers, CabinetMessagingPage switch exhaustif sur le sealed state (7 cas couverts), route wrappée Scaffold dans app_router.dart, bloc + use cases enregistrés GetIt (pro_di.dart, data_registration.dart), flutter analyze vert, 14 tests bloc+widget verts ; crash navigateur/contexte pendant le run, pas une exception app — même famille que #2734/#3135. Le seul finding distinct détecté depuis sur cette route (#3227, console-errors) a suivi son propre traitement | doublon périmé — ferme #3136 |
| flow C step 1 | praticien | 2026-07-02 | déjà documenté faux positif usePathUrlStrategy (cf. notes méthodologiques : #3188-#3191 « postés puis fermés ») — #3190 resté ouvert par erreur ; les runs suivants passent l'étape 1 | faux positif — ferme #3190 |
| / (root) | patient | 2026-07-02 | déjà documenté — ligne « ferme #3199 #3201 » du 01/07 (méthode C, CSS ::placeholder) ; l'issue n'avait pas été fermée effectivement | faux positif — ferme #3199 |
| /reviews | patient | 2026-07-02 | même famille méthode C : marker = CSS `flt-text-editing::placeholder` capté dans le DOM, aucun hit grep source ; route OK au run 2026-07-01T20:47 | faux positif — ferme #3167 |

## Notes méthodologiques harness

- **app_practicien utilise `usePathUrlStrategy()`** (voir `front/apps/app_practicien/lib/bootstrap.dart:11`) — contrairement à patient/secretariat qui routent via `#hash`, praticien utilise des URLs "propres" (pathname). `window.location.hash` y est **toujours vide** ; utiliser `window.location.pathname` + `history.pushState()` + `dispatchEvent(new PopStateEvent('popstate'))` pour naviguer et vérifier la route courante sur cette app. Piège rencontré en Étape 4.5 (Flow C) : deux faux positifs `onboarding-flow-broken` postés puis fermés (#3188, #3189, #3190, #3191) avant correction.
- Formulaire `/register-pro` (praticien) : long formulaire scrollable — le dropdown "Spécialité" et le bouton "Créer mon compte" sont sous le fold à 800px de haut ; scroller `page.mouse.wheel(0, 700)` ×2 (avec `mouse.move` préalable pour cibler le glass pane) avant d'interagir. Faux positifs #3192, #3194, #3195 (jusqu'à interaction correcte).
- Bug réel confirmé (pas un faux positif) : `POST /v1/pro/register` répond 201 mais `ProRegisterPage`/`ProRegisterCubit` ne déclenche aucune navigation post-succès — voir #3198.
- **Run 2026-07-02T07:06 — la course register-pro récidive une nouvelle fois** malgré la fermeture de #3192/#3196/#3198 : POST 201 confirmé, mais le pathname final rebondit sur `/login` au lieu de `/cabinet-setup`. Non re-posté (dup <24h de #3198, fermé 05:49 le même jour) — à surveiller au prochain run une fois la fenêtre anti-doublon expirée si toujours reproduit.
- **Nouvelle classe de bug détectée ce run (2026-07-02) : bannière d'erreur visible en app malgré 0 console.error et 0 failedRequests** ("Erreur lors du chargement...", DioException probablement avalée par une course sur l'auth-interceptor/token-storage — famille déjà documentée sur #3199/#3167/#3135). Touche 8 routes patient (`/`, `/documents`, `/financial`, `/mes-rdv`, `/messaging`, `/notifications`, `/profile`, `/reviews`, issues #3216-#3223) et 2 routes praticien (`/`, `/messages`, issues #3225, #3227). Le harness classe désormais explicitement ce cas comme finding même quand les critères mécaniques (whiteRatio/console/requests) indiqueraient un faux OK — toujours lire la capture d'écran.
- Onboarding flow B (secretariat, invitation) : fix confirmé au run 2026-07-02 (PR #3209 / commit `0264b7f5`) — token invalide correctement rejeté (400 `invitation_invalid`), écran "Invitation invalide" affiché. Flow OK.
- `/bookable-slots` (secretariat) : lacune backend réelle toujours présente au run 2026-07-02 (405 sur `GET /v1/cabinet/slots`, seule la route `POST` est enregistrée dans `api/src/lib.rs`) — non re-posté (dup #3055/#3173 fermés <24h), à re-vérifier au prochain run.

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | "Erreur serveur lors du chargement du tableau de bord", 0 console.error / 0 failedRequests — #3216 |
| /a2ui-demo | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /account-setup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /appointments | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /book | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /coverage-setup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /documents | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3217 |
| /financial | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3218 |
| /forgot-password | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /login | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /mes-rdv | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3219 |
| /messaging | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3220 |
| /notifications | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3221 |
| /oubliettes | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | runtime OK ; feature-gap séparé détecté (mock hardcodé) — #3224 |
| /profile | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3222 |
| /rdv/test-appt-id/prepare | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — (non re-testé ce run, hors cap) |
| /reviews | 2026-07-01 | 2026-07-02T07:06:22.000Z | hidden-error-banner | bannière d'erreur visible, 0 console.error / 0 failedRequests — #3223 |
| /signup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /splash | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-02T07:06:22.000Z | console-errors | "Erreur serveur lors du chargement du tableau de bord" — #3225 |
| /a2ui-demo | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /agenda | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /cabinet-setup | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /consultation | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | runtime OK ; feature-gap séparé (`StubGetActsUseCase` dans ccam_picker.dart) — #3226 |
| /login | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /messages | 2026-07-01 | 2026-07-02T07:06:22.000Z | console-errors | "Erreur lors du chargement des conversations" — #3227 |
| /ordonnances | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /ordonnances/new | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /patients | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /patients/test-patient-id | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /register-pro | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | rendu formulaire OK ; le flow de soumission récidive (voir Onboarding flow C) |
| /splash | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /waiting-room | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | feature-gap dupe skip (<24h) non re-posté |
| /a2ui-demo | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /admin-membres | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | feature-gap dupe skip (<24h) non re-posté |
| /admin-secretariats | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /agenda | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /appointments | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /bookable-slots | 2026-07-01 | 2026-07-02T07:06:22.000Z | failed-requests | 405 confirmé sur GET /v1/cabinet/slots (route jamais enregistrée côté Rust) ; dupe #3055/#3173 fermés <24h, non re-posté |
| /devis | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /devis/test-devis-id | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /liste-attente | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /login | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /messages | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /onboard | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | invitation_token invalide → "Invitation invalide" (rendu valide) |
| /patients | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /salle-attente | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |
| /splash | 2026-07-01 | 2026-07-02T07:06:22.000Z | OK | — |

## Onboarding flows (Étape 4.5)

| flow | app | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| A (signup patient) | patient | 2026-07-02T07:06:22.000Z | known-issue | redirect vers /account-setup après signup échoue toujours — POST 201 puis rebond sur /login. Tracké #3100 (open), skip anti-doublon |
| B (invitation secretariat) | secretariat | 2026-07-02T07:06:22.000Z | OK | fix confirmé (PR #3209, commit 0264b7f5) — token invalide rejeté (400 invitation_invalid), "Invitation invalide" affiché correctement |
| C (register praticien) | praticien | 2026-07-02T07:06:22.000Z | known-issue | POST /v1/pro/register répond 201 mais rebond sur /login au lieu de /cabinet-setup — course BlocConsumer.listener vs auth-guard récidive malgré #3192/#3196/#3198 fermés ; non re-posté (dup <24h de #3198) |
