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
> agents QA manuels. Les runs du 2026-07-04 et 2026-07-06 ont suivi la spec
> URL-sweep historique (v5 streaming) telle que demandée, pas le nouveau
> playbook — à clarifier avec un humain si les deux doctrines doivent
> converger.

Last run: 2026-07-06T18:24:08.000Z

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
| /agenda, /liste-attente (secretariat) ; /patients/test-patient-id, /ordonnances, /ordonnances/new (praticien) ; /reset-password, /notifications (patient) | secretariat, praticien, patient | 2026-07-06 | seuil mécanique `whiteRatio > 0.995` déclenché sur des pages avec du **contenu réel** (agenda chargé après un délai réseau plus long que le sleep fixe du sweep, empty-states légitimes, bannière d'ID factice attendue, page à faible densité de texte) — voir note méthodologique whiteRatio ci-dessous | faux positifs — vérifiés à l'écran, aucune issue filée |

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
- **Piège harness confirmé au run 2026-07-04 (patient) : checkbox CGU Flutter.** Un `.click()` DOM brut sur `flt-semantics[role="checkbox"]` ne déclenche pas de vrai événement pointeur — utiliser le `.click()` natif Playwright sur le locator sémantique. Le champ "Date de naissance" est un date-picker Material (dialog), pas un input texte : ouvrir le dialog, basculer en mode "Passer à la saisie" texte, effacer la valeur pré-remplie avant de taper. **Ce piège n'est pas spécifique à `/signup` (patient)** : tout `Checkbox` Flutter web y est exposé, notamment `Key('onboarding_cgu_checkbox')` sur `/onboard` (secretariat, flow B) — un `.click()` DOM brut dessus laisse `_cguAccepted=false`, donc le bouton submit reste désactivé (`onPressed: null`), donc **aucune requête n'est envoyée et aucun message ne peut s'afficher**. C'est la cause la plus probable du finding "invalid-token message shown=false" du run 2026-07-06 (#3398) : vérifié que `AuthRepositoryImpl.register` mappe bien un 400 `invitation_invalid` vers `InvalidInviteFailure` et que `OnboardingPage` affiche l'écran "Invitation invalide" dès que `ProAuthCubit` émet `invalidInvite=true` — la chaîne applicative est intacte, donc si le message ne s'affiche pas c'est que le submit n'a jamais eu lieu côté harness.
- **Piège harness confirmé au run 2026-07-04 (praticien) : contamination de buffer console/réseau entre routes.** Une requête de la route précédente peut se résoudre pendant la fenêtre de capture de la route suivante si le settle-delay après login est trop court, produisant un faux `/devis` en `console-errors` — corrigé en isolant le re-test avec un délai de stabilisation plus long après login.
- **Run 2026-07-06 — le sandbox d'exécution n'a que 64 Mo de `/dev/shm`**, cause classique de crash du renderer Chromium headless sous charge WebGL/CanvasKit (`Target page, context or browser has been closed` en cours de run, parfois précédé de `WebGL: CONTEXT_LOST_WEBGL`). Lancer `chromium.launch({ args: ['--disable-dev-shm-usage', '--no-sandbox'] })` réduit la fréquence mais ne l'élimine pas totalement sur de longues sessions single-page multi-navigation — en cas de crash, ré-essayer la route dans un **navigateur/contexte frais** plutôt que de continuer sur la même page.
- **Run 2026-07-06 — le seuil `whiteRatio > 0.92` (v5 streaming, tel que spécifié) est essentiellement inutilisable tel quel sur cette UI.** Deux problèmes distincts : (1) calculer le ratio sur les **octets bruts du fichier PNG compressé** (DEFLATE) n'a aucune corrélation avec la couleur des pixels — il faut décoder le PNG (ex. `pngjs`) et lire les vrais canaux RGB ; (2) le fond d'app est `#fafaf9` (quasi-blanc) sur les 3 apps, donc **une page avec du contenu réel affiche déjà ~95-98 % de pixels quasi-blancs** (peu de texte/chrome sur un design minimaliste) — un seuil à 0.92 classifierait presque toutes les pages OK en faux `blank-canvas`. Ajusté empiriquement à un seuil interne `> 0.995` (au-dessus du bruit des pages réelles) **combiné à une relecture manuelle systématique de la capture** avant de conclure — jamais de POST automatique sur ce seul critère. `canvasCount` s'est avéré toujours égal à 0 sur les 3 apps (CanvasKit ne semble pas exposer de `<canvas>` compté par ce sélecteur ici) — signal à ne pas utiliser seul non plus.
- **Run 2026-07-06 — piège harness confirmé : `.click()` natif Playwright (pas seulement le `.click()` DOM brut déjà documenté) est parfois insuffisant sur `flt-semantics[role="button"|"checkbox"]`.** Root cause probable : le pointeur synthétique de Playwright n'active pas toujours le gesture recognizer de Flutter. Fix fiable : dispatcher soi-même la séquence `pointerover/pointerenter/pointerdown/pointerup/click` via `document.elementFromPoint(cx, cy)` au centre du `boundingBox()` (motif déjà utilisé dans `qa-verify-3398.js`, généralisé ici en helper `realClick()`). **Exception** : le bootstrap `flt-semantics-placeholder` (qui active l'arbre sémantique une seule fois par chargement de page) a besoin d'un vrai `.click()` DOM (`el.click()` via `page.evaluate`) — un dispatch de pointer-events dessus ne l'active pas.
- **Run 2026-07-06 — nouvelle classe de race harness : `NubiaTextField` recâble `onChanged: (_) => setState(() {})` sur toute la page à chaque frappe.** Un `.fill()` Playwright (instantané) peut arriver pendant un rebuild du sous-arbre sémantique déclenché par le champ précédent, et la valeur retombe silencieusement à vide (observé aléatoirement sur `Nom`, `Téléphone` selon les runs). Deux mitigations : (1) taper via `locator.pressSequentially(value, {delay:25})` puis **vérifier** `inputValue() === value` avec 3 tentatives (`fillFieldRobust()`) ; (2) cibler les inputs **par index** (`page.locator('input').nth(i)`), pas par label — `NubiaTextField` ajoute un suffixe hint/erreur au `aria-label` dès que le champ est non-vide (ex. "Mot de passe" → "Mot de passe\n8 caractères minimum..."), ce qui casse un `getByLabel(label, {exact:true})` capturé avant la frappe.
- **Run 2026-07-06 — le menu popup de `DropdownButton` (Spécialité, `/register-pro` praticien) n'est pas atteignable par un locator Playwright** (ni par rôle, ni par texte) — probablement peint uniquement en CanvasKit sans nœud sémantique séparé pour chaque item. Fix : navigation clavier une fois le menu ouvert (`ArrowDown` puis `Enter`), fiable à 2/2 runs consécutifs.
- **Run 2026-07-06 — nouveau bug bloquant sur Onboarding Flow A, distinct de #3384/#3397 (tous deux déjà fermés, tous deux à l'étape account-setup) : `PATCH /v1/account/coverage` rejette 422 dès que `mutuelle.amc` est renseigné sans `mutuelle.numero_adherent`**, alors que l'UI labelle explicitement ce champ "Numéro adhérent (**optionnel**)". Root cause : `PatchCoverageMutuelle` (`api/src/auth/mod.rs:2345-2349`) déclare `numero_adherent: String` (requis, pas `Option`), donc Serde rejette le body dès que `mutuelle` est présent sans les deux clés. Bloque l'étape finale du flow pour tout patient qui suit l'invite de l'UI. Tracké #3434 (P0) — **repris et fermé par flutter-agent en cours de ce même run** (PR #3435, fix frontend : envoie toujours `amc`+`numero_adherent` avec `?? ''` au lieu d'omettre la clé, + bannière d'erreur persistante au lieu d'un SnackBar transitoire). Root cause backend (champ non-optionnel malgré le contrat UI) non touchée par le fix — workaround frontend, à surveiller si une régression future réintroduit l'omission de la clé.
- **Run 2026-07-06 — Onboarding Flow C (register praticien) reconfirmé OK pour la 2e fois consécutive** (2 runs indépendants ce run, tous deux POST 201 → `/cabinet-setup` sans rebond sur `/login`). La course auth-guard documentée depuis #3192 et une longue lignée de faux "fix" semble bien résolue — recommandé de considérer cette classe de bug close sauf régression future.
- **Run 2026-07-06 — nouveau feature-gap praticien `/devis` (Méthode A, grep) : l'action "envoyer le devis au patient" est un mock local, aucun appel réseau.** `DevisBloc._onSendRequested` (`devis_bloc.dart:67-79`) émet `DevisSent` immédiatement après une mutation locale, sans jamais appeler `POST /v1/cabinet/quotes/:id/send` (qui n'existe d'ailleurs pas côté backend). Silencieux côté UI (rendu normal, aucun marker visible) — trouvé uniquement par grep source, pas par le scan DOM (Méthode C). Distinct de l'ancien #3370 (fermé, décrivait l'ancien écran 100 % stub list/detail, déjà remplacé par un vrai rendu depuis le 2026-07-04). Tracké #3436 (P3).

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, contenu réel affiché |
| /a2ui-demo | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /account-setup | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | testé via Onboarding flow A (atteint, formulaire soumis avec succès) |
| /appointments | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé — carte + liste praticiens réelle |
| /book | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /coverage-setup | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK (rendu) | rendu formulaire OK ; soumission avec mutuelle+numéro vide → 422 (#3434, fixé en cours de run par #3435 — à reconfirmer au prochain run) |
| /documents | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, liste réelle |
| /financial | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, liste réelle |
| /forgot-password | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (contexte non-authentifié) |
| /login | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (contexte non-authentifié) |
| /mes-rdv | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /messaging | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, liste réelle |
| /notifications | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (whiteRatio mécanique 0.997 faux positif — 1 notification réelle affichée) |
| /oubliettes | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, feature-gap #3224 toujours corrigé |
| /pharmacy | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /pharmacy/search | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /pharmacy/send | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /pharmacy/orders | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /pharmacy/orders/:id | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /profile | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /profile/dependents | 2026-07-04 | 2026-07-06T18:24:08.000Z | OK | corrigé depuis #3386, reconfirmé 0 console.error |
| /profile/consents | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /profile/notifications | 2026-07-04 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /rdv/test-appt-id/prepare | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /reset-password | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (contexte non-authentifié) — "Ce lien de réinitialisation est invalide." sans token, attendu |
| /reviews | 2026-07-01 | 2026-07-04T23:51:28.000Z | OK | — (non re-testé ce run, hors cap) |
| /signup | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (contexte non-authentifié + via Onboarding flow A) |
| /splash | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (contexte non-authentifié) |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | corrigé depuis #3383 — 0 console.error, 0 failed-request (today-notes 404 disparu) |
| /a2ui-demo | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /agenda | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /cabinet-setup | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, atteint via Onboarding flow C ×2 |
| /consultation | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | runtime OK ; feature-gap déjà tracké — #3226 |
| /devis | 2026-07-04 | 2026-07-06T18:24:08.000Z | OK (rendu) | rendu OK ; nouveau feature-gap sur l'action d'envoi (Méthode A grep) — #3436 |
| /login | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé via login flow |
| /messages | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, liste de conversations réelle |
| /ordonnances | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé — état vide légitime "Aucune ordonnance en cours" |
| /ordonnances/new | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé — état vide légitime "Nouvelle ordonnance" |
| /patients | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /patients/test-patient-id | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | bannière "Impossible de charger le patient." avec un ID factice = comportement attendu (reconfirmé) |
| /register-pro | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | rendu + flow de soumission complet OK, **2e confirmation indépendante ce run** (voir Onboarding flow C) |
| /splash | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé via login flow |
| /waiting-room | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| / | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, KPI + états vides corrects |
| /a2ui-demo | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /admin-membres | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | runtime OK (403 attendu, rôle secretary) ; feature-gap #3381 corrigé (InviteMemberUseCase désormais réellement câblé, vérifié par lecture source — non testable en direct avec ce rôle) |
| /admin-secretariats | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | feature-gap #3382 corrigé (idem) |
| /agenda | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé (whiteRatio mécanique 1.000 faux positif dû à un délai réseau > sleep fixe du sweep — contenu réel confirmé à l'écran après re-test avec délai plus long) |
| /appointments | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /bookable-slots | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, grille de créneaux réelle |
| /devis | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /devis/test-devis-id | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | bannière "404" avec un ID factice = comportement attendu (reconfirmé) |
| /liste-attente | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé — état vide légitime "Pas d'attente" |
| /login | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé via login flow |
| /messages | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /onboard | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | invitation_token invalide → "Invitation invalide" (reconfirmé, voir Onboarding flow B) |
| /patients | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé, cloisonnement clinique respecté |
| /salle-attente | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé |
| /splash | 2026-07-01 | 2026-07-06T18:24:08.000Z | OK | reconfirmé via login flow |

## Onboarding flows (Étape 4.5)

| flow | app | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| A (signup patient) | patient | 2026-07-06T18:24:08.000Z | broken puis fixé | signup + account-setup (birth_date, #3384) désormais OK de bout en bout ; **nouveau bug** trouvé une étape plus loin, coverage-setup : PATCH /v1/account/coverage 422 si mutuelle renseignée sans numéro adhérent (pourtant labellé optionnel) — #3434 (P0), **fixé en cours de ce run** par PR #3435 (workaround frontend : envoie toujours les 2 clés) — à reconfirmer au prochain run |
| B (invitation secretariat) | secretariat | 2026-07-06T18:24:08.000Z | OK | reconfirmé — fix PR #3209 tient toujours (400 invitation_invalid, checkbox CGU cochée via pointer-events réels, "Invitation invalide" affiché de bout en bout) |
| C (register praticien) | praticien | 2026-07-06T18:24:08.000Z | OK | **2e confirmation indépendante consécutive** ce run (2/2) : POST 201 → /cabinet-setup atteint sans rebond sur /login, dropdown Spécialité navigué au clavier. La course auth-guard (#3192 et sa longue lignée) est considérée résolue sauf régression future |
