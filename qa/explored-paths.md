# QA Explored Paths

Last run: 2026-06-25 00:20

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` (pseudo-sélecteur champ texte) capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — feature complète, ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` (champ saisie du thread) | faux positif — feature complète (CabinetMessagingPage, bloc, thread), ferme #2734 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-25 | OK | — |
| /appointments | 2026-06-24 | 2026-06-25 | OK | — |
| /mes-rdv | 2026-06-24 | 2026-06-25 | OK | — |
| /documents | 2026-06-24 | 2026-06-25 | OK | — |
| /financial | 2026-06-24 | 2026-06-25 | OK | — |
| /profile | 2026-06-24 | 2026-06-25 | OK | — |
| /messaging | 2026-06-24 | 2026-06-25 | OK | — |
| /notifications | 2026-06-24 | 2026-06-25 | console-errors | console-errors |

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
