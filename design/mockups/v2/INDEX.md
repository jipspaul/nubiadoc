# design-v2 — index écran → maquette (référence de conformité)

> **Propriétaire** de la correspondance « écran de l'app ⟷ maquette v2 ». C'est CE fichier
> que l'agent QA lit pour savoir, pour un écran live donné, quelle maquette ouvrir et comparer.
> Les maquettes elles-mêmes sont les `.html` de ce dossier ; les tokens/composants canoniques
> restent dans [`../../03-design-system/`](../../03-design-system/) (01-tokens.md, 02-composants.md,
> 03-flutter-theme.md). Un fait = un seul fichier : ici on ne décrit **que** le mapping.

## Comment l'utiliser

1. Ouvre la maquette dans le navigateur : `file:///workspace/nubiadoc-qa/design/mockups/v2/<fichier>`.
   Les `* v2.html` sont **autonomes** (seules les polices viennent de Google Fonts) ; les 4 maquettes
   agrégées (`Nubia *.html`) et les pages d'analyse dépendent de `lib/` + des `.jsx` de ce dossier.
2. Ouvre l'écran live correspondant dans la même session, au même viewport.
3. Compare : palette/tokens, composants design-v2 attendus, typo, espacements, structure.
4. La colonne « Sources » donne les fichiers Dart de l'écran — c'est là qu'on root-cause un écart.

Les 4 maquettes de [`..`](..) (`Nubia Patient/Back-office/Spotlight/Comparatif`) sont la version
**agrégée et antérieure** de ce même design ; en cas de divergence, **ce dossier `v2/` fait foi**.

## Patient (`app_patient` — mobile 390×844 d'abord)

| Écran | Maquette | Sources |
|---|---|---|
| Accueil | `Patient Accueil v2.html` | `features/home/*` |
| Shell 5 onglets | `Patient Accueil v2.html` (barre d'onglets) | `features/dashboard/dashboard_page.dart`, `nubia_design_system/…/nubia_bottom_nav.dart` |
| Mes RDV | `Patient Mes RDV v2.html` | `features/mes_rdv/mes_rdv_page.dart`, `features/appointments/appointments_{state,event}.dart` |
| Réservation (créneaux → confirmation) | `Patient Réservation v2.html` | `features/appointments/{appointments_page,appointments_state,booking_confirmation_page}.dart` |
| Devis & reste à charge | `Patient Facturation v2.html` | `features/financial/{financial_page,financial_state}.dart`, `widgets/{quote_list_view,quote_detail_view,financial_format_utils}.dart` |
| Messagerie | `Patient Messagerie v2.html` | `features/messaging/{messaging_page,messaging_state}.dart` |
| Notifications | `Patient Notifications v2.html` | `features/notifications/{notifications_page,notification_deep_link_handler}.dart` |
| Consentements | `Patient Consentements v2.html` | `features/consents/consents_page.dart` |
| Mon plan de soins | `Patient Mon plan de soins v2.html` | `features/treatment_plans/treatment_plans_page.dart` |
| Passeport implantaire | `Patient Passeport implantaire v2.html` | `features/implant_passport/implant_passport_page.dart` |
| Suivi de commande pharmacie | `Patient Suivi de commande v2.html` | `features/pharmacy_orders/{order_detail_page,widgets/order_timeline,widgets/pickup_qr_card}.dart` |
| Documents, Proches & Profil | `Patient Documents et Proches v2.html` | `features/{documents/documents_page,dependents/dependents_page,profile/profile_page}.dart` |
| Invitation d'un proche adulte | `Patient Invitation proche adulte.html` | `features/dependents/` |
| Tunnel web recherche + réservation (SSR) | `Patient Web Tunnel reservation.html` | `api/src/web_tunnel/`, modèle `Slot`/`SlotChip` de `features/mes_rdv/modify_rdv_page.dart` |

## Praticien (`app_practicien` — tablette/PC 1280×800 d'abord)

| Écran | Maquette | Sources |
|---|---|---|
| Tableau de bord | `Praticien Tableau de bord v2.html` | `features/dashboard/{dashboard_page,today_notes_card}.dart` |
| Consultation au fauteuil | `Praticien Consultation v2.html` | `features/consultation_clinique/{consultation_clinique_page,consultation_clinique_state}.dart`, `features/dental_chart/tooth_grid.dart` |
| Consultation sur PC (responsive) | `Praticien Consultation PC.html` | `router/app_router.dart` |
| Dossier patient | `Praticien Dossier patient v2.html` | `features/patients/patient_fiche.dart` |
| Plans de traitement | `Praticien Plan de traitement v2.html` | `features/treatment_plans/{treatment_plans_page,treatment_plans_cubit}.dart` |
| Ordonnance (composition) | `Praticien Ordonnance v2.html` | `features/ordonnances/{ordonnance_new_page,ordonnances_state}.dart`, `widgets/{prescription_template_picker,send_to_pharmacy_card}.dart` |
| Travaux de laboratoire | `Praticien Travaux labo v2.html` | `features/lab_work/{lab_work_orders_page,lab_work_orders_state}.dart` |
| Salle d'attente | `Praticien Salle d'attente v2.html` | `features/waiting_room/waiting_room_page.dart` |
| Versions PC (praticien + pharmacie) | `Ecrans PC - Praticien et Pharmacie.html` | `router/app_router.dart` + écrans concernés |

## Secrétariat (`app_secretariat` — PC 1280×800 d'abord)

| Écran | Maquette | Sources |
|---|---|---|
| Tableau de bord | `Secretariat Tableau de bord v2.html` | `features/dashboard/dashboard_page.dart` |
| Agenda du cabinet (grille semaine) | `Secretariat Agenda v2.html` | `features/agenda/{agenda_page,agenda_state}.dart`, `lib/app.dart` |
| Architecture de navigation | `Secretariat Navigation v2.html` | `router/app_router.dart` |
| Salle d'attente (poste comptoir) | `Secretariat Salle d'attente v2.html` | `features/waiting_room/{waiting_room_page,waiting_room_bloc,waiting_room_state}.dart` |
| Fiches patients (administratif) | `Secretariat Fiches patients v2.html` | `features/patients/{patients_page,patients_state}.dart` |
| Devis | `Secretariat Devis v2.html` | `features/devis/{devis_page,devis_state}.dart` |
| Encaissements / rapprochement bancaire | `Secretariat Encaissements v2.html` | `features/cabinet_payouts/{cabinet_payouts_page,cabinet_payouts_state}.dart` |
| Demandes de stock | `Secretariat Stock v2.html` | `features/stock/{stock_page,create_stock_request_dialog,stock_state}.dart` |
| Messagerie interne | `Secretariat Messagerie interne v2.html` | `features/team_messages/team_messages_page.dart` |
| Mesure de protection (dépôt + vérification) | `Mesure de protection - depot et verification.html` | `app_patient/features/dependents/`, `features/audit_log/audit_log_page.dart` |

## Pharmacie (`app_pharmacie` — PC/tablette)

| Écran | Maquette | Sources |
|---|---|---|
| File des commandes | `Pharmacie File des commandes v2.html` | `features/orders/{orders_page,orders_state}.dart` |
| Délivrance & scan de retrait | `Pharmacie Delivrance v2.html` | `features/order_detail/{order_detail_page,widgets/pickup_info_card}.dart`, `features/pickup_scan/{pickup_scan_page,pickup_scan_cubit}.dart` |
| Devis & Stock | `Pharmacie Devis et Stock v2.html` | `features/{devis/devis_page,stock/stock_page}.dart` |
| Messagerie patient | `Pharmacie Messagerie v2.html` | `features/pharma_messaging/pharma_messaging_page.dart` |

## Infirmière (`app_infirmiere` — mobile 390×844)

L'app infirmière (soins à domicile, v1) **n'a pas encore de maquette v2 dédiée** : aucun écran de
ce dossier ne la couvre. Sa conformité s'évalue donc contre les **tokens et composants** du design
system ([`../../03-design-system/01-tokens.md`](../../03-design-system/01-tokens.md),
[`02-composants.md`](../../03-design-system/02-composants.md)) et, par analogie, contre les patterns
mobile de `Patient Accueil v2.html` (shell, cartes, typo, espacements).

| Écran | Maquette | Sources |
|---|---|---|
| Connexion | _(aucune — tokens + patterns patient)_ | `features/login/login_page.dart` |
| Accueil / offres | _(aucune — tokens + patterns patient)_ | `features/home/infirmiere_home_page.dart`, `features/nurse/nurse_cubit.dart` |

> Écrire ces maquettes est un manque **connu et assumé**, pas un bug à re-signaler à chaque ronde :
> un écart de token sur l'app infirmière reste rapportable, mais « maquette v2 absente » ne l'est pas.

## Transverse (pas un écran : décisions & synthèses)

| Sujet | Fichier |
|---|---|
| Backlog UI/UX (25 défauts sur les 4 apps + 5 fondations) | `Nubia Backlog UI-UX.html` |
| Correctifs immédiats | `Nubia Correctifs immediats.html` |
| Parcours transverse | `Nubia Parcours transverse.html` |
| Index de livraison | `Nubia Index de livraison.html` |
| Contrat de données | `Nubia Contrat de donnees.html` |
| Questions ouvertes / arbitrages 1 à 3 | `Questions ouvertes - arbitrages 1 a 3.html` |
| Arbitrage 1 — bases légales des consentements | `Arbitrage 1 - Bases legales des consentements.html` |
| Arbitrage 2 — majorité des proches mineurs | `Arbitrage 2 - Majorite des proches mineurs.html` |
| Comparatif back-office V1 (sidebar) / V2 (Spotlight) | `Nubia Comparatif.html`, `Nubia Spotlight.html`, `Nubia Back-office.html` |

## Captures

`screenshots/` contient les rendus d'origine des maquettes (référence rapide, sans avoir à
les ouvrir). Ce ne sont **pas** des captures de l'app live — celles-là vivent sur la branche
`qa-screenshots-snapshot` (cf. `vps/qa-nubiadoc/qa-run.sh` côté agentInfra).
