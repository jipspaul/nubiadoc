# QA Explored Paths

Last run: 2026-06-25T22:17

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` (pseudo-sélecteur champ texte) capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — feature complète, ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` (champ saisie du thread) | faux positif — feature complète (CabinetMessagingPage, bloc, thread), ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` (champ texte dans la bottom sheet de sélection patient) | faux positif — feature complète (AgendaPage, AgendaBloc, navigation semaine, cards RDV, empty state), ferme #2732 |
| /notifications | patient | 2026-06-25 | QA-20260625-8 (T2755.b) : BlocBuilder + GetIt déjà corrigés par commits antérieurs (enregistrement NotificationsBloc, BlocBuilder exhaustif #2662, try/catch handlers) ; flutter analyze vert (vérifié 2026-06-25) | déjà résolu — ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | QA-20260625-14 (T2736.b+c) : route /ordonnances retourne Scaffold+AppBar+OrdonnancesPage (≥3 widgets), OrdonnancesBody couvre Initial/Loading/Created/Signed/Loaded/Error avec NubiaEmptyState/NubiaErrorWidget, OrdonnancesBloc enregistré dans GetIt (pro_di.dart) ; flutter analyze vert (vérifié 2026-06-26) | déjà résolu — ferme #2853 #2854 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | OK | — |
| /appointments | 2026-06-24 | 2026-06-25 | OK | — |
| /mes-rdv | 2026-06-24 | 2026-06-25 | OK | — |
| /documents | 2026-06-24 | 2026-06-25 | OK | — |
| /financial | 2026-06-24 | 2026-06-25 | OK | — |
| /profile | 2026-06-24 | 2026-06-26 | OK | faux positif #2728 confirmé — feature complète, flutter analyze vert |
| /messaging | 2026-06-24 | 2026-06-25 | OK | — |
| /notifications | 2026-06-24 | 2026-06-26 | OK | re-vérifié 2026-06-26 : bloc try/catch, BlocBuilder exhaustif, BlocProvider router, flutter analyze vert — ferme #2833 |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | OK | — |
| /agenda | 2026-06-24 | 2026-06-25 | OK | — |
| /patients | 2026-06-24 | 2026-06-25 | OK | — |
| /messages | 2026-06-24 | 2026-06-25 | OK | — |
| /consultation | 2026-06-24 | 2026-06-25 | OK | — |
| /ordonnances | 2026-06-24 | 2026-06-25 | OK | — |
| /waiting-room | 2026-06-24 | 2026-06-25 | OK | — |
| /a2ui-demo | 2026-06-24 | 2026-06-25 | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | OK | — |
| /agenda | 2026-06-24 | 2026-06-25 | OK | — |
| /appointments | 2026-06-24 | 2026-06-25 | OK | — |
| /bookable-slots | 2026-06-24 | 2026-06-25 | OK | — |
| /devis | 2026-06-24 | 2026-06-25 | OK | — |
| /liste-attente | 2026-06-24 | 2026-06-25 | OK | — |
| /patients | 2026-06-24 | 2026-06-25 | OK | — |
| /salle-attente | 2026-06-24 | 2026-06-25 | OK | — |
