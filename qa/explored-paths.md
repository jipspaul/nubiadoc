# QA Explored Paths

Last run: 2026-06-25T22:16

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` (pseudo-sélecteur champ texte) capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — feature complète, ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` (champ saisie du thread) | faux positif — feature complète (CabinetMessagingPage, bloc, thread), ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` (champ texte dans la bottom sheet de sélection patient) | faux positif — feature complète (AgendaPage, AgendaBloc, navigation semaine, cards RDV, empty state), ferme #2732 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /appointments | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /mes-rdv | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /documents | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /financial | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /profile | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /messaging | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /notifications | 2026-06-24 | 2026-06-25 | login-failed | login-failed |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /agenda | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /patients | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /messages | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /consultation | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /ordonnances | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /waiting-room | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /a2ui-demo | 2026-06-24 | 2026-06-25 | login-failed | login-failed |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /agenda | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /appointments | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /bookable-slots | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /devis | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /liste-attente | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /patients | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
| /salle-attente | 2026-06-24 | 2026-06-25 | login-failed | login-failed |
