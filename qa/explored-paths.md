# QA Explored Paths

Last run: 2026-07-01T03:26:27.611Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter placeholder | faux positif — ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter placeholder | faux positif — ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter placeholder | faux positif — ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing | faux positif — ferme #2920-#2935 |
| Login | ALL | 2026-06-30 | canvas click coords: email y=380, pw y=420, btn y=490 | fix appliqué run 13:15 |
| Auth routes | ALL | 2026-06-30 | Flutter HTML renderer white background = not blank | fix: skip white ratio for auth routes |
| /signup | patient | 2026-06-30 | CSS Flutter placeholder (NubiaTextField) | faux positif — ferme #3083 |
| /messages | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA (pas d'exception app — bloc + widget déjà couverts, tous states gérés, tests verts) | faux positif — ferme #3136 |
| /patients/:id | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA (pas d'exception app — PatientsBloc._onDetailLoad try/catch + SafeEmitMixin, PatientDetailPage/BlocConsumer couvre Loading/Loaded/Error, 17 tests bloc+widget verts) | faux positif — ferme #3132 |
| /agenda | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA (pas d'exception app — AgendaBloc couvre Initial/Loading/Loaded/Error avec try/catch + SafeEmitMixin, AgendaPage/AgendaBody gèrent tous les states, route déjà wrappée dans BlocProvider, 20 tests bloc+widget verts) | faux positif — ferme #3134 |
| / | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA — DashboardBloc et TodayNotesBloc couvrent tous les states avec try/catch, _DashboardContent gère Initial/Loading/Loaded/Error via switch exhaustif, TodayNotesCard gère tous les states, route non wrappée en BlocProvider (normal : bloc créé dans bodyBuilder), tests bloc+widget verts | fix: try/catch ajouté TodayNotesBloc — ferme #3133 |
| /ordonnances | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA (pas d'exception app — OrdonnancesBloc._onCreate/_onSign ont déjà try/catch + emit Error, OrdonnancesBody gère tous les states (Initial/Loading/Created/SigningInProgress/Signed/Loaded vide/Error), route déjà wrappée dans BlocProvider (dans OrdonnancesPage), tests bloc+widget verts) | faux positif — ferme #3138 |
| /cabinet-setup | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA (pas d'exception app — CabinetInfoCubit.submit déjà en try/catch via SafeEmitMixin, CabinetInfoPage/BlocConsumer couvre Idle/Loading/Success/Failure, Key('cabinet_setup_scaffold') déjà présente, route déjà wrappée dans BlocProvider, tests bloc+widget verts) | faux positif — ferme #3140 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /signup | 2026-06-30 | 2026-07-01T03:27:04.737Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T03:27:07.289Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T03:27:09.841Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T03:27:42.147Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T03:26:27.611Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T03:27:19.202Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T03:27:37.048Z | OK | — |
| / | 2026-06-30 | 2026-07-01T03:27:16.650Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T03:27:21.733Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T03:27:24.303Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T03:27:26.870Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T03:27:29.414Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T03:27:31.949Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T03:27:34.498Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T03:27:39.601Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T03:27:14.111Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-07-01 | 2026-07-01T03:27:00.236Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-07-01T03:28:11.652Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T03:28:41.500Z | OK | — |
| / | 2026-06-30 | 2026-07-01T03:28:18.632Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T03:28:21.181Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T03:28:23.714Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T03:28:26.250Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T03:28:31.335Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T03:28:33.879Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T03:28:36.413Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T03:28:44.032Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T03:28:16.098Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T03:28:38.948Z | OK | — |
| /patients/test-patient-id | 2026-07-01 | 2026-07-01T03:28:28.781Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-07-01T03:29:21.028Z | console-errors | Failed to load resource: the server responded with a status  |
| /messages | 2026-06-30 | 2026-07-01T03:29:53.130Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T03:29:55.682Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T03:29:58.250Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T03:29:35.293Z | OK | — |
| / | 2026-06-30 | 2026-07-01T03:29:27.653Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T03:29:30.198Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T03:29:42.928Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T03:29:37.829Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T03:29:40.381Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T03:29:45.481Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T03:29:32.761Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T03:29:48.027Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T03:29:25.099Z | OK | — |
| /devis/test-devis-id | 2026-07-01 | 2026-07-01T03:29:50.580Z | OK | — |
