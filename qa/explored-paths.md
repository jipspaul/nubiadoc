# QA Explored Paths

Last run: 2026-07-01T20:47:05.000Z

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
| /bookable-slots | secretariat | 2026-06-30 | déjà résolu — BookableSlotsBloc wrap try/catch + SafeEmitMixin, BookableSlotsBody (BlocBuilder) couvre tous les states (Initial/Loading/Loaded vide/Loaded/Error via NubiaErrorWidget), route câblée dans app_router.dart (BlocProvider > BookableSlotsPage > Scaffold), bloc enregistré dans GetIt (pro_di.dart), 16 tests bloc+widget verts (bookable_slots_test.dart) | faux positif — ferme #3055 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage, BlocBuilder exhaustif, GetIt, flutter analyze vert | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via location.hash (in-page, sans page.goto) |
| / et /account-setup | patient | 2026-07-01 | méthode C : scan DOM incluait le texte de balises `<style>` injectées (CSS `::placeholder`) via `.textContent` d'un `div` ancêtre | faux positif — ferme #3199 #3201. Fix harness : exclure `style`/`script` du scan DOM + filtre anti-CSS-boilerplate (`::placeholder`, `caret-color`, `-webkit-autofill`) |
| flow C (register praticien) | praticien | 2026-07-01 | déjà résolu — détections 20:25–20:36 antérieures au merge du fix #3194 (21:11, `context.go(cabinetSetup)` sur ProRegisterSuccess dans le listener du BlocConsumer) + follow-ups #3193 (08aac18b) et #3195 (7c4968b0, guestOnlyRoutes anti-course du guard) ; test widget de non-régression ajouté (pro_register_page_test.dart : ProRegisterSuccess → /cabinet-setup) | doublons périmés — ferme #3192 #3196 #3198 |

## Notes méthodologiques harness

- **app_practicien utilise `usePathUrlStrategy()`** (voir `front/apps/app_practicien/lib/bootstrap.dart:11`) — contrairement à patient/secretariat qui routent via `#hash`, praticien utilise des URLs "propres" (pathname). `window.location.hash` y est **toujours vide** ; utiliser `window.location.pathname` + `history.pushState()` + `dispatchEvent(new PopStateEvent('popstate'))` pour naviguer et vérifier la route courante sur cette app. Piège rencontré en Étape 4.5 (Flow C) : deux faux positifs `onboarding-flow-broken` postés puis fermés (#3188, #3189, #3190, #3191) avant correction.
- Formulaire `/register-pro` (praticien) : long formulaire scrollable — le dropdown "Spécialité" et le bouton "Créer mon compte" sont sous le fold à 800px de haut ; scroller `page.mouse.wheel(0, 700)` ×2 (avec `mouse.move` préalable pour cibler le glass pane) avant d'interagir. Faux positifs #3192, #3194, #3195 (jusqu'à interaction correcte).
- Bug réel confirmé (pas un faux positif) : `POST /v1/pro/register` répond 201 mais `ProRegisterPage`/`ProRegisterCubit` ne déclenche aucune navigation post-succès — voir #3198.

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /a2ui-demo | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /account-setup | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /appointments | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /book | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /coverage-setup | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /documents | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /financial | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /login | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /mes-rdv | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /messaging | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /notifications | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /oubliettes | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /profile | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /reviews | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /signup | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /a2ui-demo | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /agenda | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /cabinet-setup | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /consultation | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /login | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /messages | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /ordonnances | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /ordonnances/new | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /patients | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /patients/test-patient-id | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /register-pro | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /waiting-room | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /a2ui-demo | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /admin-membres | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /admin-secretariats | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /agenda | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /appointments | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /bookable-slots | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /devis | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /devis/test-devis-id | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /liste-attente | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /login | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /messages | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /onboard | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /patients | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /salle-attente | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T20:47:05.000Z | OK | — |

## Onboarding flows (Étape 4.5)

| flow | app | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| A (signup patient) | patient | 2026-07-01T20:47:05.000Z | known-issue | redirect vers /account-setup après signup échoue — reste sur /login. Déjà tracké #3100 (open), skip anti-doublon |
| B (invitation secretariat) | secretariat | 2026-07-01T20:47:05.000Z | FAIL | invitation_token invalide n'affiche PAS de message "Invitation invalide" — le formulaire de finalisation de compte reste utilisable sans validation du token. #3187 |
| C (register praticien) | praticien | 2026-07-01T20:47:05.000Z | FAIL | POST /v1/pro/register répond 201 (compte créé) mais aucune navigation post-succès, formulaire reste affiché sans feedback. #3198 |
