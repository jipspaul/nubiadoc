# QA Explored Paths

Last run: 2026-07-01T02:18:28.294Z

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
| /signup | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| / | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| / | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /ordonnances/new | 20260630 | 2026-07-01T02:18:28.294Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| / | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T02:18:28.294Z | OK | — |

