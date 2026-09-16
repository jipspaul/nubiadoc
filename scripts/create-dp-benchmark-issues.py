#!/usr/bin/env python3
"""Crée sur Forgejo les issues de parité issues de `docs/17-benchmark-dental-pilot.md`
(§4.1 et §4.2 — le §4.3 « lourd / externe » est exclu par décision).

Usage :
    FORGEJO_TOKEN=... python3 scripts/create-dp-benchmark-issues.py --dry-run   # valide et affiche
    FORGEJO_TOKEN=... python3 scripts/create-dp-benchmark-issues.py             # crée

Contrat orchestrateur (agentInfra/orchestrator/src/preflight.ts) :
  - assignee = login Forgejo == nom du Service k8s de l'agent
  - body avec les 7 sections obligatoires + au moins un chemin backtické
  - dépendances natives Forgejo ; label `agent:go` uniquement sur les racines,
    les dépendantes sont promues automatiquement à la fermeture.
Idempotent : une issue dont le titre existe déjà (ouverte) n'est pas recréée.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

DRY = "--dry-run" in sys.argv
PACE = 0.35  # s entre deux appels — le cluster sature vers 20 événements/s

# ---------------------------------------------------------------------------
# Données
# ---------------------------------------------------------------------------

RUST = "rust-agent"
PG = "postgres-agent"
FL = ["flutter-agent", "flutter-agent-2"]
_fl_i = 0


def flutter():
    global _fl_i
    a = FL[_fl_i % len(FL)]
    _fl_i += 1
    return a


RLS_REF = "`db/migrations/0158_create_patient_tag.sql`"
PLAN = "`docs/17-benchmark-dental-pilot.md`"

ISSUES = []  # dicts : id, title, assignee, deps, objectif, etat, procedure, done, files, branch


def issue(id_, title, assignee, deps, objectif, etat, procedure, done, files, extra_ref=""):
    ISSUES.append(dict(id=id_, title=title, assignee=assignee, deps=deps, objectif=objectif,
                       etat=etat, procedure=procedure, done=done, files=files, extra_ref=extra_ref))


# --- F1 Opportunités du moment -------------------------------------------------
issue("DP-F1.a", "[DP-F1.a] API — vue « opportunités du moment » du cabinet", RUST, [],
      "Exposer `GET /v1/cabinet/opportunities` : devis envoyés sans réponse depuis > 7 j, devis acceptés sans RDV "
      "planifié, factures impayées depuis > 30 j, patients vus récemment sans prochain RDV, anniversaires du jour. "
      "C'est le widget central du dashboard de Dental Pilot ; toutes les données existent déjà en base.",
      ["Devis et statuts : `api/src/cabinet_quotes.rs`, relances : `api/src/quote_relances.rs`",
       "Impayés : `api/src/patient_alerts.rs` (`OVERDUE_INVOICE_DELAY_DAYS = 30`)",
       "Patients sans RDV : logique de `api/src/recall_campaigns.rs`",
       "Manque : aucun endpoint agrégé, aucune vue « opportunités »"],
      ["Créer `api/src/cabinet_opportunities.rs` : une requête SQL par catégorie, RLS cabinet via le GUC existant, "
       "chaque ligne = `{kind, patient_id, patient_name, amount_cents?, since_days, quote_id?|invoice_id?}` + un compteur et un total par catégorie",
       "Enregistrer la route dans `api/src/routes/billing.rs` (ou `misc.rs`), RBAC : rôles cabinet (manager, doctor, secretary)",
       "Tests d'intégration sqlx : un cabinet avec un devis ancien, une facture échue, un patient sans RDV ; vérifier l'isolation tenant",
       "`cargo test -p nubia-api` vert, `cargo clippy` sans warning"],
      ["`GET /v1/cabinet/opportunities` répond 200 avec les 5 catégories et leurs totaux",
       "Test d'isolation : un autre cabinet ne voit rien",
       "Documenté dans `docs/12-api-reference.md` (section back-office)"],
      ["`api/src/cabinet_quotes.rs`", "`api/src/patient_alerts.rs`", "`api/src/recall_campaigns.rs`",
       "`api/src/routes/billing.rs`", "`api/AGENTS.md`"])
issue("DP-F1.b", "[DP-F1.b] Front — widget « opportunités du moment » (praticien + secrétariat)", flutter(), ["DP-F1.a"],
      "Afficher les opportunités sur les deux dashboards, chaque ligne cliquable vers le devis / la facture / le patient, "
      "avec les montants en jeu par catégorie.",
      ["Dashboards : `front/apps/app_practicien/lib/features/dashboard/`, `front/apps/app_secretariat/lib/features/dashboard/`",
       "Repositories : `front/packages/nubia_data/lib/src/repositories/`",
       "Manque : modèle, repository, bloc et widget"],
      ["Ajouter le modèle dans `nubia_domain`, le repository dans `nubia_data` (endpoint `GET /v1/cabinet/opportunities`)",
       "Créer `opportunities_card.dart` dans chaque app (ou un widget partagé dans `nubia_design_system`) : 5 lignes, compteur, total, chevron vers l'écran cible",
       "Tests widget + bloc ; `flutter analyze` et `flutter test` verts dans les deux apps"],
      ["Widget visible sur les deux dashboards avec données réelles de l'API",
       "Clic sur une ligne → navigation vers l'entité",
       "Tests widget passent"],
      ["`front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`",
       "`front/apps/app_secretariat/lib/features/dashboard/`", "`front/AGENTS.md`"])

# --- F2 Tâches assignables ---------------------------------------------------------
issue("DP-F2.a", "[DP-F2.a] DB — table `cabinet_task` (tâches assignables du cabinet)", PG, [],
      "Poser la table des tâches internes du cabinet : titre, description, assignee, patient/RDV optionnels, échéance, "
      "statut, créateur. Base des to-do secrétariat et des notes à l'assistante depuis un RDV.",
      ["Aucune table de tâches. Pattern RLS tenant de référence : " + RLS_REF,
       "Membres et rôles : `db/migrations/0018_cabinet_membership_active.sql`"],
      ["Migration `db/migrations/NNNN_create_cabinet_task.sql` : `id, cabinet_id, title, description, assignee_user_id, patient_id, appointment_id, due_date, status (open|done|cancelled), created_by, created_at, done_at`",
       "RLS fail-closed sur `app.current_cabinet_id`, index `(cabinet_id, status, due_date)`",
       "Tests pgTAP : isolation tenant, contrainte de statut",
       "`make db-test` (ou la cible équivalente de `db/AGENTS.md`) vert"],
      ["Migration appliquée, pgTAP vert", "`db/AGENTS.md` respecté (numérotation, commentaire d'en-tête)"],
      [RLS_REF, "`db/AGENTS.md`", "`db/migrations/0193_create_lab_work_order.sql`"])
issue("DP-F2.b", "[DP-F2.b] API — CRUD des tâches + notification à l'assigné", RUST, ["DP-F2.a"],
      "Exposer `/v1/cabinet/tasks` (liste filtrable par assigné / statut / patient, création, mise à jour, clôture) "
      "et notifier l'assigné (push + in-app) à la création. Permettre la création d'une tâche depuis un RDV "
      "(« prépare le guide chirurgical »).",
      ["Notifications : `api/src/notify.rs`, `api/src/notifications.rs`, kinds dans `api/src/reminders.rs`",
       "Manque : module tâches"],
      ["Créer `api/src/cabinet_tasks.rs` (list/create/patch/complete), route dans `api/src/routes/misc.rs`",
       "Nouveau kind de notification `task_assigned` (vérifier la contrainte CHECK des kinds, cf. `db/migrations/0194_reminder_nullable_appointment_recall_kinds.sql` — ajouter une migration si besoin)",
       "`POST /v1/appointments/:id/tasks` = raccourci qui pré-remplit patient + RDV",
       "Tests d'intégration + RBAC"],
      ["CRUD fonctionnel et testé", "L'assigné reçoit une notification", "Documenté dans `docs/12-api-reference.md`"],
      ["`api/src/notify.rs`", "`api/src/notifications.rs`", "`api/src/appointments_create.rs`", "`api/src/routes/misc.rs`"])
issue("DP-F2.c", "[DP-F2.c] Front — écran Tâches + widget dashboard + note à l'assistante depuis un RDV", flutter(), ["DP-F2.b"],
      "Liste « tâches à réaliser » (actives / historique, filtre assigné) sur les dashboards praticien et secrétariat, "
      "création rapide, clôture en un tap, et un champ « tâche pour l'assistante » dans le formulaire de RDV.",
      ["Dashboards et agenda : `front/apps/app_practicien/lib/features/dashboard/`, `front/apps/app_secretariat/lib/features/appointments/`",
       "Manque : tout le front tâches"],
      ["Modèle + repository `nubia_data`, bloc, `tasks_card.dart` + `tasks_page.dart`",
       "Dans la création de RDV secrétariat : champ optionnel « tâche pour … » (assigné + texte) → `POST /v1/appointments/:id/tasks`",
       "Notification in-app à réception de `task_assigned`",
       "Tests widget/bloc, `flutter analyze` vert"],
      ["Widget sur les deux dashboards", "Création depuis un RDV", "Clôture en un tap"],
      ["`front/apps/app_secretariat/lib/features/appointments/`", "`front/apps/app_practicien/lib/features/dashboard/pending_actions_card.dart`", "`front/AGENTS.md`"])

# --- F3 Prothèses du jour ------------------------------------------------------------
issue("DP-F3.a", "[DP-F3.a] DB — statut d'expédition et de réception sur `lab_work_order`", PG, [],
      "Ajouter `shipped_at`, `received_at`, `tracking_ref` et un statut enrichi (`sent|in_progress|shipped|received|fitted`) "
      "pour suivre la prothèse jusqu'à la pose et alerter la veille si elle n'est pas arrivée.",
      ["`db/migrations/0193_create_lab_work_order.sql` : `status`, `sent_at`, `expected_return_at`, `appointment_id`, `purchase_price_cents` existent",
       "Manque : dates d'expédition / réception, statut détaillé"],
      ["Migration ALTER : colonnes + CHECK du statut étendu (sans casser les valeurs existantes)",
       "Index `(cabinet_id, expected_return_at)` pour la vue du jour",
       "pgTAP : transitions de statut"],
      ["Migration + pgTAP verts"],
      ["`db/migrations/0193_create_lab_work_order.sql`", "`db/AGENTS.md`"])
issue("DP-F3.b", "[DP-F3.b] API — prothèses du jour + alerte « prothèse non reçue la veille »", RUST, ["DP-F3.a"],
      "`GET /v1/cabinet/lab-work-orders/today` (poses prévues aujourd'hui / demain avec statut) et une alerte "
      "`patient_alerts` quand un RDV de pose est demain et que la prothèse n'est pas `received`.",
      ["`api/src/lab_work_orders.rs` : CRUD existant", "`api/src/patient_alerts.rs` : moteur d'alertes"],
      ["Endpoint `today` joignant `appointment` (date de pose) et `lab_work_order`",
       "PATCH de statut `shipped` / `received` avec horodatage",
       "Nouvelle alerte dans `patient_alerts.rs` : `prosthesis_not_received` (RDV J+1, statut < received)",
       "Tests d'intégration"],
      ["Endpoint `today` et PATCH de statut testés", "Alerte visible dans `GET /v1/patients/:id/alerts` et le dashboard"],
      ["`api/src/lab_work_orders.rs`", "`api/src/patient_alerts.rs`", "`api/src/routes/clinical.rs`"])
issue("DP-F3.c", "[DP-F3.c] Front — widget « prothèses du jour » + statuts d'expédition", flutter(), ["DP-F3.b"],
      "Widget dashboard praticien « prothèses du jour » (patient, dent, labo, statut coloré) et boutons de statut "
      "dans l'écran de suivi labo.",
      ["`front/apps/app_practicien/lib/features/lab_work/` : écran existant", "Manque : widget et statuts"],
      ["Repository : `today` + PATCH statut", "Widget `prostheses_today_card.dart`", "Chips de statut dans `lab_work`", "Tests widget"],
      ["Widget sur le dashboard praticien", "Changement de statut depuis le front"],
      ["`front/apps/app_practicien/lib/features/lab_work/`", "`front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`"])

# --- F4 Relance impayé --------------------------------------------------------------------
issue("DP-F4.a", "[DP-F4.a] API — relance d'une facture impayée au patient", RUST, [],
      "`POST /v1/invoices/:id/reminder` : envoie au patient une relance (in-app + push, e-mail si configuré) avec le "
      "reste dû et un lien vers l'écran financier de l'app patient ; trace la relance (date, canal).",
      ["Factures et paiements : `api/src/billing.rs`, `api/src/billing_payments.rs`",
       "Alertes impayés : `api/src/patient_alerts.rs`", "Envoi : `api/src/notify.rs`, `api/src/reminder_dispatch.rs`",
       "Manque : action de relance et sa trace"],
      ["Migration légère : table `invoice_reminder(id, invoice_id, cabinet_id, sent_at, channel, sent_by)` — pattern " + RLS_REF,
       "Endpoint + kind de notification `invoice_reminder` (payload sans PII, cf. `docs/07-conformite.md`)",
       "Garde-fou : pas plus d'une relance par 7 jours par facture (409 sinon)",
       "Tests"],
      ["Relance envoyée et tracée", "Garde-fou 7 j testé", "Doc API mise à jour"],
      ["`api/src/billing.rs`", "`api/src/patient_alerts.rs`", "`api/src/notify.rs`", "`api/src/routes/billing.rs`"])
issue("DP-F4.b", "[DP-F4.b] Front — bouton « relancer » sur une facture impayée + réception côté patient", flutter(), ["DP-F4.a"],
      "Bouton « Relancer le patient » sur les factures échues (secrétariat + praticien) avec l'historique des relances ; "
      "côté app patient, la notification ouvre l'écran financier.",
      ["Secrétariat devis/factures : `front/apps/app_secretariat/lib/features/devis/`", "Patient : `front/apps/app_patient/lib/features/financial/`"],
      ["Repository + bouton + liste des relances", "Deep-link notification → `financial`", "Tests widget"],
      ["Bouton visible uniquement si échue", "Historique affiché", "Deep-link patient fonctionnel"],
      ["`front/apps/app_secretariat/lib/features/devis/`", "`front/apps/app_patient/lib/features/financial/`"])

# --- F5 Devis : pièces jointes + attestation d'information ----------------------------------------
issue("DP-F5.a", "[DP-F5.a] DB — pièces jointes de devis et attestation d'information", PG, [],
      "Tables `quote_attachment` (devis ↔ document ou modèle : consentement, ordonnance, courrier) et "
      "`quote_information_attestation` (texte, signé le, référence de signature).",
      ["Devis : `db/migrations/0051_quote_signed_immutable.sql` et suivantes", "Documents : table `document`", "Manque : les deux tables"],
      ["Migration : `quote_attachment(id, quote_id, cabinet_id, kind (consent|prescription|letter|other), document_id?, template_ref?, created_at)`",
       "Migration : `quote_information_attestation(id, quote_id, cabinet_id, body, signed_at, signature_ref, patient_id)`",
       "RLS tenant + lecture patient sur ses propres devis (pattern `0134_quote_patient_read_exclude_draft.sql`)",
       "pgTAP"],
      ["Migrations + pgTAP verts"],
      ["`db/migrations/0134_quote_patient_read_exclude_draft.sql`", RLS_REF, "`db/AGENTS.md`"])
issue("DP-F5.b", "[DP-F5.b] API — envoi de devis avec pièces jointes + attestation d'information signée", RUST, ["DP-F5.a"],
      "Choisir des pièces à joindre à l'envoi d'un devis (consentement par type d'acte, ordonnance, courrier), les inclure "
      "dans l'e-mail et l'espace patient, et faire signer une attestation d'information avant la signature du devis.",
      ["Envoi et signature : `api/src/cabinet_quotes.rs`, `api/src/quote_signature.rs`, `api/src/quote_relance_dispatch.rs`",
       "Documents : `api/src/documents.rs`", "Manque : pièces jointes, attestation"],
      ["`POST/GET/DELETE /v1/quotes/:id/attachments`", "L'envoi (`send`) liste les pièces dans l'e-mail et l'app patient",
       "`GET/POST /v1/quotes/:id/attestation` + `POST …/attestation/sign` (même mécanique que `/sign`)",
       "Règle : si une attestation existe et n'est pas signée, `POST /sign` du devis renvoie 409",
       "Tests"],
      ["Pièces jointes visibles côté patient", "Attestation signable, bloque la signature du devis tant que non signée", "Doc API"],
      ["`api/src/cabinet_quotes.rs`", "`api/src/quote_signature.rs`", "`api/src/documents.rs`"])
issue("DP-F5.c", "[DP-F5.c] Front praticien — sélection des pièces jointes à l'envoi du devis + attestation", flutter(), ["DP-F5.b"],
      "Dans l'écran devis praticien : panneau « documents à joindre » (consentements filtrés par type d'acte, ordonnance, "
      "courrier), message personnalisable, et génération de l'attestation d'information.",
      ["`front/apps/app_practicien/lib/features/devis/`"],
      ["Repository attachments/attestation", "UI de sélection multi + aperçu", "Tests widget"],
      ["Envoi avec pièces depuis le front", "Attestation créée depuis le front"],
      ["`front/apps/app_practicien/lib/features/devis/`"])
issue("DP-F5.d", "[DP-F5.d] Front patient — lire les pièces jointes et signer l'attestation avant le devis", flutter(), ["DP-F5.b"],
      "Dans l'app patient : les pièces jointes listées sur le devis, l'attestation d'information à lire et signer, "
      "puis seulement le bouton de signature du devis.",
      ["`front/apps/app_patient/lib/features/treatment_plans/` et le flux `/sign` existant"],
      ["Repository", "Écran attestation (texte + signature) réutilisant le composant de signature existant", "Verrou UI : devis signable après attestation", "Tests widget"],
      ["Parcours complet testé sur données fictives"],
      ["`front/apps/app_patient/lib/features/treatment_plans/`", "`front/apps/app_patient/lib/features/documents/`"])

# --- F6 Bibliothèque de consentements ---------------------------------------------------------
issue("DP-F6.a", "[DP-F6.a] DB — `consent_template` : bibliothèque de consentements éclairés (catalogue + cabinet)", PG, [],
      "Table de modèles de consentement éclairé par type d'acte, avec un catalogue standard seedé (chirurgie orale, "
      "parodontale, implants, prothèse amovible partielle/totale, fixe unitaire/plurale, orthodontie, pédodontie, "
      "extraction, endodontie) et des variantes propres au cabinet.",
      ["Modèle à copier : `db/migrations/0166_create_prescription_template.sql` (catalogue partagé + tenant)",
       "`consent_record` trace un consentement mais aucune bibliothèque n'existe"],
      ["Migration : `consent_template(id, cabinet_id NULL = catalogue, act_category, title, body_markdown, version, is_active)` + RLS (global lisible par tous, tenant en écriture)",
       "Seed de 10 modèles en français, texte générique non médical-décisionnel (à faire relire, marquer `-- seed v1`)",
       "pgTAP"],
      ["Migration + seed + pgTAP verts"],
      ["`db/migrations/0166_create_prescription_template.sql`", "`db/AGENTS.md`"])
issue("DP-F6.b", "[DP-F6.b] API — CRUD des modèles de consentement + rendu pour un patient", RUST, ["DP-F6.a"],
      "Lister / créer / modifier les modèles de consentement, et rendre un modèle pour un patient et un devis "
      "(substitution du nom, des dents, des actes) en document joignable au devis.",
      ["Modèles de CR : `api/src/cr_templates.rs` (structure à reprendre)", "Documents : `api/src/documents.rs`"],
      ["`api/src/consent_templates.rs` : list (catalogue + cabinet), create, patch, `POST /v1/consent-templates/:id/render` → document",
       "Route dans `api/src/routes/cr_prescriptions.rs`", "Tests"],
      ["CRUD + rendu testés", "Document rendu joignable via DP-F5.b"],
      ["`api/src/cr_templates.rs`", "`api/src/documents.rs`", "`api/src/routes/cr_prescriptions.rs`"])
issue("DP-F6.c", "[DP-F6.c] Front praticien — écran « Modèles de consentement »", flutter(), ["DP-F6.b"],
      "Écran de gestion des modèles (catalogue en lecture, copies cabinet éditables), aperçu, et sélection depuis le devis.",
      ["Pas d'écran de modèles côté praticien"],
      ["Repository + écran liste/édition markdown + aperçu", "Tests widget"],
      ["Écran fonctionnel, modèle cabinet créé depuis le front"],
      ["`front/apps/app_practicien/lib/features/devis/`", "`front/packages/nubia_design_system/`"])

# --- F7 Courriers types ---------------------------------------------------------------------------
issue("DP-F7.a", "[DP-F7.a] API — moteur de courriers types : substitution, en-tête/pied cabinet, PDF", RUST, [],
      "Rendre un `letter_template` pour un patient (et un correspondant) : substitution `{{patient.prenom}}`, "
      "`{{cabinet.nom}}`, `{{praticien.rpps}}`, `{{rdv.date}}`… ; en-tête et pied standardisés (logo, coordonnées, "
      "RPPS) ; sortie PDF stockée en document patient.",
      ["`db/migrations/0167_create_letter_template.sql` : schéma seul, **moteur de substitution non fait**",
       "Génération PDF : voir comment `api/src/cabinet_quotes_export.rs` produit ses PDF", "Documents : `api/src/documents.rs`"],
      ["`api/src/letters.rs` : `GET /v1/letter-templates`, `POST /v1/letter-templates`, `POST /v1/patients/:id/letters` `{template_id, correspondent_id?, overrides}` → document PDF",
       "Substitution sûre (placeholder inconnu → 422 avec la liste), échappement",
       "Seed de 4 courriers types : convocation, relance, courrier confrère, attestation de présence (migration légère)",
       "Tests unitaires du moteur + intégration"],
      ["Rendu PDF d'un courrier avec en-tête cabinet", "Placeholders documentés dans `docs/12-api-reference.md`"],
      ["`db/migrations/0167_create_letter_template.sql`", "`api/src/cabinet_quotes_export.rs`", "`api/src/documents.rs`"])
issue("DP-F7.b", "[DP-F7.b] Front praticien — écran « Courrier » : modèle, correspondant, aperçu, PDF, envoi", flutter(), ["DP-F7.a"],
      "Écran de rédaction d'un courrier depuis la fiche patient : choix du modèle, correspondant, champs libres, aperçu, "
      "PDF, ajout aux documents du patient.",
      ["`front/apps/app_practicien/lib/features/patients/`", "Aucun écran courrier"],
      ["Repository + écran + aperçu PDF (viewer existant des documents)", "Tests widget"],
      ["Courrier généré depuis la fiche patient et visible dans ses documents"],
      ["`front/apps/app_practicien/lib/features/patients/`", "`front/apps/app_practicien/lib/features/ordonnances/`"])

# --- F8 Correspondants côté cabinet ---------------------------------------------------------------
issue("DP-F8.a", "[DP-F8.a] DB — `cabinet_correspondent` + lien patient adressé", PG, [],
      "Carnet de correspondants du cabinet (nom, spécialité, e-mail, téléphone, adresse, RPPS) et lien "
      "« patient adressé par » pour mesurer les adressages et le CA apporté.",
      ["`db/migrations/0176_patient_correspondent.sql` et `0129_patient_referring_doctor.sql` : liens patient ↔ médecin en texte libre",
       "Manque : entité correspondant partagée au cabinet"],
      ["Migration : `cabinet_correspondent(id, cabinet_id, display_name, specialty, email, phone, address, rpps, notes)` + RLS",
       "`patient.referred_by_correspondent_id` (nullable, FK) — ou table de lien si multiple",
       "pgTAP"],
      ["Migrations + pgTAP verts"],
      ["`db/migrations/0176_patient_correspondent.sql`", RLS_REF])
issue("DP-F8.b", "[DP-F8.b] API — correspondants : CRUD, adressages, CA apporté, courriers envoyés", RUST, ["DP-F8.a", "DP-F7.a"],
      "`/v1/cabinet/correspondents` CRUD + `GET /v1/cabinet/correspondents/:id/stats` (patients adressés, CA facturé "
      "sur ces patients, courriers envoyés) ; le moteur de courriers (DP-F7.a) accepte un `correspondent_id`.",
      ["Facturation : `api/src/billing.rs`", "Courriers : `api/src/letters.rs` (DP-F7.a)"],
      ["`api/src/cabinet_correspondents.rs`", "Stats par jointure billing", "Tests"],
      ["CRUD + stats testés", "Courrier avec correspondant rendu"],
      ["`api/src/billing.rs`", "`api/src/patient_detail.rs`"])
issue("DP-F8.c", "[DP-F8.c] Front secrétariat — écran « Correspondants » + champ « adressé par » sur le patient", flutter(), ["DP-F8.b"],
      "Liste des correspondants avec stats (patients adressés, CA), fiche, et sélection « adressé par » dans la fiche patient.",
      ["`front/apps/app_secretariat/lib/features/patients/`"],
      ["Repository + écran liste/fiche + champ patient", "Tests widget"],
      ["Écran opérationnel"],
      ["`front/apps/app_secretariat/lib/features/patients/`"])

# --- F9 Briefs ---------------------------------------------------------------------------------
issue("DP-F9.a", "[DP-F9.a] API — briefs du jour / de la semaine / des prothèses à poser", RUST, ["DP-F3.b"],
      "`GET /v1/cabinet/briefs/{day|week|prostheses}` : résumé structuré (RDV par praticien avec motif, patients "
      "nouveaux, actes prévus, prothèses à poser, tâches ouvertes) + export PDF.",
      ["Agenda : `api/src/appointments_read.rs`", "Prothèses : DP-F3.b", "Aucun brief"],
      ["`api/src/cabinet_briefs.rs` avec les trois vues", "PDF via le même moteur que DP-F7.a si disponible, sinon HTML imprimable", "Tests"],
      ["Trois endpoints testés", "PDF ou HTML imprimable"],
      ["`api/src/appointments_read.rs`", "`api/src/lab_work_orders.rs`"])
issue("DP-F9.b", "[DP-F9.b] Front — bouton « Brief » sur l'agenda (jour / semaine / prothèses)", flutter(), ["DP-F9.a"],
      "Bouton dans l'agenda praticien et secrétariat ouvrant le brief (lecture + impression).",
      ["`front/apps/app_practicien/lib/features/agenda/`", "`front/apps/app_secretariat/lib/features/agenda/`"],
      ["Repository + écran brief + impression/partage", "Tests widget"],
      ["Brief consultable depuis les deux agendas"],
      ["`front/apps/app_practicien/lib/features/agenda/`", "`front/apps/app_secretariat/lib/features/agenda/`"])

# --- F10 Objectifs, occupation, CA ---------------------------------------------------------------
issue("DP-F10.a", "[DP-F10.a] DB — `practitioner_objective` (objectif mensuel par praticien)", PG, [],
      "Table des objectifs de CA mensuels par praticien et par cabinet.",
      ["Stats : `api/src/cabinet_stats.rs` ; aucune table d'objectif"],
      ["Migration `practitioner_objective(id, cabinet_id, provider_id, month date, target_cents, created_by)` UNIQUE(cabinet_id, provider_id, month), RLS", "pgTAP"],
      ["Migration + pgTAP verts"],
      [RLS_REF, "`db/AGENTS.md`"])
issue("DP-F10.b", "[DP-F10.b] API — KPI praticien : CA jour / mois / par centre, objectif, taux d'occupation", RUST, ["DP-F10.a"],
      "`GET /v1/me/kpis?period=` : facturé et encaissé du jour, du mois, par cabinet ; objectif du mois et % atteint ; "
      "taux d'occupation (créneaux réservés / créneaux ouverts) ; RDV du jour ; rappels en attente. CRUD des objectifs pour le manager.",
      ["`api/src/cabinet_stats.rs`, `api/src/dashboard.rs`", "Créneaux ouvrables : `api/src/scheduling.rs`, `bookable_slots`"],
      ["`api/src/practitioner_kpis.rs` + objectifs", "Occupation calculée sur la semaine courante", "Tests"],
      ["Endpoint testé multi-cabinet", "Objectifs CRUD"],
      ["`api/src/cabinet_stats.rs`", "`api/src/dashboard.rs`", "`api/src/scheduling.rs`"])
issue("DP-F10.c", "[DP-F10.c] Front praticien — tuiles KPI (CA, objectif, occupation) sur le dashboard", flutter(), ["DP-F10.b"],
      "Quatre tuiles en tête du dashboard praticien : CA du mois vs objectif (jauge), RDV du jour, rappels en attente, "
      "taux d'occupation ; sélecteur de centre si multi-cabinet ; saisie de l'objectif pour le manager.",
      ["`front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`"],
      ["Repository + tuiles + jauge", "Tests widget"],
      ["Tuiles affichées avec données réelles"],
      ["`front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`", "`front/packages/nubia_design_system/`"])

# --- F11 Catégories d'actes activables, mode ortho ---------------------------------------------------
issue("DP-F11.a", "[DP-F11.a] DB — `cabinet_act_category_setting` (catégories d'actes activées par cabinet)", PG, [],
      "Activer / désactiver par cabinet les catégories d'actes (consultation, soins conservateurs, endo, paro, prothèse, "
      "ortho, chirurgie, implanto, imagerie, ATM, esthétique, appareillages…) pour alléger l'interface (mode « full ortho »).",
      ["Catalogue : `db/migrations/0119_ccam_act_catalog.sql`, `0225_ccam_act_catalog_extend.sql` — vérifier qu'une colonne de catégorie existe, sinon l'ajouter"],
      ["Migration : colonne `category` sur le catalogue si absente (backfill par plage de codes CCAM, documenté) + table `cabinet_act_category_setting(cabinet_id, category, enabled)` RLS", "pgTAP"],
      ["Migration + pgTAP verts"],
      ["`db/migrations/0119_ccam_act_catalog.sql`", "`db/migrations/0225_ccam_act_catalog_extend.sql`"])
issue("DP-F11.b", "[DP-F11.b] API — filtrage du catalogue par catégories activées + réglage cabinet", RUST, ["DP-F11.a"],
      "`GET/PUT /v1/cabinet/settings/act-categories` et filtrage de `GET /v1/ccam-acts` par catégories activées (paramètre pour tout voir).",
      ["`api/src/ccam_acts.rs`, `api/src/ngap_acts.rs`"],
      ["Endpoint de réglage + filtre", "Tests"],
      ["Filtre effectif et testé"],
      ["`api/src/ccam_acts.rs`", "`api/src/practitioner_favorite_acts.rs`"])
issue("DP-F11.c", "[DP-F11.c] Front praticien — réglage des catégories + mode « full ortho »", flutter(), ["DP-F11.b"],
      "Écran de réglage (interrupteurs par catégorie), preset « full ortho », et masquage des onglets/catégories désactivés "
      "dans la consultation clinique.",
      ["`front/apps/app_practicien/lib/features/consultation_clinique/`", "`front/apps/app_practicien/lib/features/cabinet/`"],
      ["Repository + écran + preset + masquage", "Tests widget"],
      ["Mode ortho masque les catégories non ortho"],
      ["`front/apps/app_practicien/lib/features/consultation_clinique/`", "`front/apps/app_practicien/lib/features/cabinet/`"])

# --- F12 Stock par salle + import ---------------------------------------------------------------------
issue("DP-F12.a", "[DP-F12.a] DB — `stock_location` (stock principal + stock par salle)", PG, [],
      "Localisations de stock (principal, salle 1, salle 2…) et quantité par localisation.",
      ["`db/migrations/0192_create_stock_inventory.sql`, `stock_items` — une seule quantité par article"],
      ["Migration : `stock_location(id, cabinet_id, name, is_main)` + `stock_item_location(item_id, location_id, quantity, threshold)` ; backfill = tout au principal", "RLS, pgTAP"],
      ["Migration + backfill + pgTAP verts"],
      ["`db/migrations/0192_create_stock_inventory.sql`"])
issue("DP-F12.b", "[DP-F12.b] API — stock par salle, transferts, import de lignes (CSV / facture saisie)", RUST, ["DP-F12.a"],
      "Localisations CRUD, mouvement entre localisations, seuils par localisation, et `POST /v1/stock/import` (CSV "
      "`ref;libellé;quantité;prix`) pour entrer une facture fournisseur sans OCR.",
      ["`api/src/stock_items.rs`, `api/src/consultation_act_stock.rs` (décrément par acte : préciser la localisation par défaut du praticien)"],
      ["Endpoints + adaptation du décrément (localisation par défaut = principal)", "Import CSV avec rapport d'erreurs par ligne", "Tests"],
      ["Transfert et import testés", "Décrément par acte inchangé fonctionnellement"],
      ["`api/src/stock_items.rs`", "`api/src/consultation_act_stock.rs`", "`api/src/ccam_stock_mappings.rs`"])
issue("DP-F12.c", "[DP-F12.c] Front — stock par salle + import CSV (praticien, secrétariat)", flutter(), ["DP-F12.b"],
      "Onglets par localisation, transfert, alertes par salle, écran d'import CSV avec rapport.",
      ["`front/apps/app_practicien/lib/features/stock/`", "`front/apps/app_secretariat/lib/features/stock/`"],
      ["Repository + UI + import", "Tests widget"],
      ["Écrans opérationnels dans les deux apps"],
      ["`front/apps/app_practicien/lib/features/stock/`", "`front/apps/app_secretariat/lib/features/stock/`"])

# --- F13 Étiquettes stérilisation ---------------------------------------------------------------------
issue("DP-F13.a", "[DP-F13.a] API — étiquettes de stérilisation (PDF, QR par sachet) + rattachement à un patient par scan", RUST, [],
      "`GET /v1/sterilization/cycles/:id/labels.pdf` (une étiquette par sachet : code, cycle, date, péremption, QR) et "
      "`POST /v1/sterilization/pouches/:code/use` `{patient_id, consultation_id}` pour tracer l'usage par scan.",
      ["`api/src/sterilization.rs` ; codes sachets uniques `db/migrations/0191_sterilized_pouch_code_unique.sql`"],
      ["Génération PDF d'étiquettes (format 2 colonnes, imprimable sur planches standard)", "Endpoint d'usage par code, idempotent", "Tests"],
      ["PDF généré", "Usage tracé par scan"],
      ["`api/src/sterilization.rs`", "`db/migrations/0191_sterilized_pouch_code_unique.sql`"])
issue("DP-F13.b", "[DP-F13.b] Front — impression des étiquettes + scan caméra du sachet dans la consultation", flutter(), ["DP-F13.a"],
      "Bouton « Imprimer les étiquettes » sur un cycle, et scan du QR (caméra téléphone / webcam) depuis la consultation "
      "pour rattacher le sachet au patient — réutiliser le scanner de `app_pharmacie/pickup_scan`.",
      ["`front/apps/app_pharmacie/lib/features/pickup_scan/` (scanner existant)", "Stérilisation côté praticien / secrétariat à localiser"],
      ["Extraire le scanner dans un package partagé si nécessaire", "UI impression + scan", "Tests widget"],
      ["Scan rattache un sachet à la consultation"],
      ["`front/apps/app_pharmacie/lib/features/pickup_scan/`", "`front/apps/app_practicien/lib/features/consultation_clinique/`"])

# --- F14 Reprise de données -----------------------------------------------------------------------------
issue("DP-F14.a", "[DP-F14.a] API — pipeline de reprise de données : upload, dry-run, mapping, rapport, import CSV patients/RDV", RUST, [],
      "Construire le pipeline générique de reprise (upload d'un fichier, analyse à blanc, rapport ligne à ligne, import "
      "idempotent, suivi dans `data_import_job`) avec un premier parseur CSV (patients + RDV, colonnes documentées, "
      "compatible export Doctolib). **Chantier critique du pilote** : aujourd'hui `data_import_job` n'est qu'une table de suivi.",
      ["`db/migrations/0168_create_data_import_job.sql` : table de suivi seulement, aucun parseur, aucun endpoint",
       "Fusion de doublons : `api/src/patient_merge.rs`, `api/src/patient_merge_candidates.rs`"],
      ["`api/src/data_import.rs` : `POST /v1/cabinet/imports` (multipart, `kind=csv_patients|csv_appointments`), `POST …/:id/dry-run`, `POST …/:id/run`, `GET …/:id` (statut, compteurs, erreurs)",
       "Trait `ImportSource` (parse → lignes normalisées) pour brancher DSIO ensuite (DP-F14.b)",
       "Idempotence par clé externe (`external_ref` sur patient / appointment — migration légère si absente)",
       "Détection de doublons via `patient_merge_candidates`", "Tests avec fichiers d'exemple dans `api/tests/fixtures/import/`"],
      ["Import CSV de 1 000 patients fictifs en < 30 s avec rapport", "Re-run sans doublon", "Doc du format CSV dans `docs/12-api-reference.md`"],
      ["`db/migrations/0168_create_data_import_job.sql`", "`api/src/patient_merge.rs`", "`api/src/appointments_create.rs`"])
issue("DP-F14.b", "[DP-F14.b] API — parseur DSIO (format d'échange des logiciels dentaires français)", RUST, ["DP-F14.a"],
      "Brancher un parseur DSIO sur le pipeline DP-F14.a : patients, praticiens, RDV, actes réalisés, règlements. "
      "**À lancer seulement quand un fichier DSIO d'exemple est disponible** (action A-22 du journal des ateliers) — "
      "ne pas inventer le format.",
      ["Pipeline : DP-F14.a", "Aucun fichier d'exemple dans le dépôt pour l'instant"],
      ["Déposer le fichier d'exemple anonymisé dans `api/tests/fixtures/import/sample.dsio`",
       "Implémenter `DsioSource` (encodage, sections, champs) d'après le fichier et la spécification fournie",
       "Mapper actes → `consultation_acts` (codes CCAM/NGAP) et règlements → `billing_payments`", "Tests sur le fichier d'exemple"],
      ["Import du fichier d'exemple complet, rapport sans erreur bloquante"],
      ["`api/src/data_import.rs`", "`api/src/consultation_act_create.rs`", "`api/src/billing_payments.rs`"],
      extra_ref=" · ⚠️ pas de label `agent:go` tant que le fichier d'exemple n'est pas déposé")
issue("DP-F14.c", "[DP-F14.c] Front secrétariat — écran « Reprise de données » : upload, analyse, rapport, import", flutter(), ["DP-F14.a"],
      "Écran d'import : choix du type, upload, résultat de l'analyse à blanc (lignes OK / en erreur avec motif), "
      "lancement, progression, rapport final téléchargeable.",
      ["`front/apps/app_secretariat/lib/features/onboarding/` (point d'entrée naturel)"],
      ["Repository + écran + polling du statut", "Tests widget"],
      ["Import CSV complet depuis le front sur données fictives"],
      ["`front/apps/app_secretariat/lib/features/onboarding/`", "`front/apps/app_secretariat/lib/features/patients/`"])

# --- F15 Suivi devis + journal --------------------------------------------------------------------------
issue("DP-F15.a", "[DP-F15.a] DB — `quote_event` (journal d'un devis)", PG, [],
      "Journal des événements d'un devis : créé, envoyé, consulté par le patient, relancé, signé, refusé, message.",
      ["Statuts de devis existants ; `audit_log` trop générique pour une timeline patient-lisible"],
      ["Migration `quote_event(id, quote_id, cabinet_id, kind, at, actor_kind (cabinet|patient|system), actor_id, meta jsonb)` + RLS + lecture patient sur ses devis", "pgTAP"],
      ["Migration + pgTAP verts"],
      ["`db/migrations/0134_quote_patient_read_exclude_draft.sql`", RLS_REF])
issue("DP-F15.b", "[DP-F15.b] API — journal du devis + vue « suivi devis » multi-praticiens", RUST, ["DP-F15.a"],
      "Émettre les `quote_event` aux bons endroits (envoi, ouverture côté patient, relance, signature, refus) ; "
      "`GET /v1/quotes/:id/events` ; `GET /v1/cabinet/quotes/overview?period=&provider=` : compteurs par statut, montant, "
      "taux de signature, délai moyen, par praticien.",
      ["`api/src/cabinet_quotes.rs`, `api/src/quote_signature.rs`, `api/src/quote_relance_dispatch.rs`, `api/src/cabinet_quotes_export.rs`",
       "Ouverture patient : endpoint de lecture du devis côté app patient"],
      ["Helper `record_quote_event`", "Hooks aux 5 endroits", "Overview SQL", "Tests"],
      ["Timeline complète sur un devis de test", "Overview par praticien"],
      ["`api/src/cabinet_quotes.rs`", "`api/src/quote_signature.rs`", "`api/src/cabinet_quotes_export.rs`"])
issue("DP-F15.c", "[DP-F15.c] Front secrétariat — écran « Suivi devis » + timeline dans le détail", flutter(), ["DP-F15.b"],
      "Tableau de tous les devis (statut, praticien, montant, dernière action, prochain RDV), filtres, export, et "
      "timeline des événements dans le détail d'un devis (secrétariat + praticien).",
      ["`front/apps/app_secretariat/lib/features/devis/`", "`front/apps/app_practicien/lib/features/devis/`"],
      ["Repository + écran overview + timeline", "Tests widget"],
      ["Écran suivi devis opérationnel"],
      ["`front/apps/app_secretariat/lib/features/devis/`", "`front/apps/app_practicien/lib/features/devis/`"])

# --- F16 Plan → séances → agenda (par règles) ------------------------------------------------------------
issue("DP-F16.a", "[DP-F16.a] DB — séances de plan de traitement + règles de découpage du cabinet", PG, [],
      "Modéliser les séances d'un plan (ordre, durée, actes, RDV lié) et les règles de découpage du cabinet "
      "(durée max, ne pas mélanger maxillaire / mandibulaire, regrouper par secteur, endo multiples autorisées).",
      ["`api/src/treatment_phases.rs` et sa table — vérifier ce qui existe (phases ≠ séances ?)"],
      ["Migration : `treatment_session(id, plan_id, cabinet_id, position, duration_min, appointment_id?, status)` + `treatment_session_act(session_id, consultation_act_id|quote_item_id)`",
       "`cabinet_session_rules(cabinet_id, max_duration_min, separate_arches bool, group_by_sector bool, multi_endo bool)`", "RLS, pgTAP"],
      ["Migrations + pgTAP verts"],
      ["`db/AGENTS.md`", RLS_REF])
issue("DP-F16.b", "[DP-F16.b] API — découpage automatique en séances (règles) + proposition de créneaux", RUST, ["DP-F16.a"],
      "`POST /v1/treatment-plans/:id/sessions/propose` : découpe les actes du plan en séances selon les règles du cabinet "
      "(sans IA, algorithme documenté) ; `POST /v1/treatment-plans/:id/sessions/:sid/slots` propose des créneaux via "
      "`scheduling` ; `POST …/schedule` crée le RDV.",
      ["`api/src/treatment_phases.rs`, `api/src/scheduling.rs`, `api/src/appointments_create.rs`"],
      ["Algorithme de découpage pur et testé unitairement (règles → séances)", "Endpoints + création de RDV liée", "Tests"],
      ["Découpage testé sur 5 scénarios", "RDV créé et lié à la séance"],
      ["`api/src/treatment_phases.rs`", "`api/src/scheduling.rs`", "`api/src/appointments_create.rs`"])
issue("DP-F16.c", "[DP-F16.c] Front praticien — onglet « Plan » : séances, réglage des règles, planification", flutter(), ["DP-F16.b"],
      "Dans le plan de traitement : liste des séances proposées (modifiables par glisser-déposer), réglage des règles du "
      "cabinet, sélection d'un créneau proposé et création du RDV.",
      ["`front/apps/app_practicien/lib/features/treatment_plans/`"],
      ["Repository + UI séances + créneaux", "Tests widget"],
      ["Parcours plan → séances → RDV complet"],
      ["`front/apps/app_practicien/lib/features/treatment_plans/`", "`front/apps/app_practicien/lib/features/agenda/`"])

# --- F17 Conformité (lot 4) -------------------------------------------------------------------------------
issue("DP-F17.a", "[DP-F17.a] DB — `compliance_item` + `custom_device_declaration` (conformité ARS, DMSM)", PG, [],
      "Échéancier de conformité du cabinet (formations obligatoires par membre, contrôles périodiques d'équipement, "
      "registres) et déclarations de dispositif médical sur mesure (DMSM) par patient.",
      ["Stérilisation tracée : `db/migrations/0190_create_sterilization_cycle.sql` ; aucune table de conformité"],
      ["Migration : `compliance_item(id, cabinet_id, kind (training|equipment_check|register|other), label, subject_user_id?, equipment_label?, due_date, recurrence_months?, status, done_at, evidence_document_id?)` + RLS",
       "Migration : `custom_device_declaration(id, cabinet_id, patient_id, consultation_act_id?, lab_name, device_description, declared_at, document_id?)` + RLS", "pgTAP"],
      ["Migrations + pgTAP verts"],
      ["`db/migrations/0190_create_sterilization_cycle.sql`", RLS_REF])
issue("DP-F17.b", "[DP-F17.b] API — conformité : échéancier, alertes, génération de la déclaration DMSM", RUST, ["DP-F17.a"],
      "CRUD des items de conformité, récurrence automatique à la clôture, alertes J-30 / J-7 / échu dans le dashboard, "
      "et `POST /v1/patients/:id/custom-device-declarations` générant le document PDF.",
      ["`api/src/patient_alerts.rs`, `api/src/sterilization.rs`, `api/src/documents.rs`"],
      ["`api/src/compliance.rs` + hooks d'alertes", "Génération PDF DMSM (moteur DP-F7.a si mergé, sinon HTML)", "Tests"],
      ["Échéancier + alertes testés", "DMSM générée"],
      ["`api/src/patient_alerts.rs`", "`api/src/sterilization.rs`", "`docs/ateliers/README.md`"],
      extra_ref=" · contenu métier (grille ARS) = action A-02 d'Abir, le moteur n'en dépend pas")
issue("DP-F17.c", "[DP-F17.c] Front secrétariat — écran « Conformité » : échéancier, alertes, DMSM", flutter(), ["DP-F17.b"],
      "Écran conformité (à venir / échu / fait, par membre et par équipement), création d'items, pièce justificative, "
      "et déclaration DMSM depuis la fiche patient.",
      ["Aucun écran conformité ; `front/apps/app_secretariat/lib/features/audit_log/` comme référence de liste"],
      ["Repository + écrans", "Tests widget"],
      ["Écran opérationnel, alertes visibles sur le dashboard"],
      ["`front/apps/app_secretariat/lib/features/audit_log/`", "`front/apps/app_secretariat/lib/features/dashboard/`"])

# --- F18 Maintenance équipements -----------------------------------------------------------------------------
issue("DP-F18.a", "[DP-F18.a] DB — `cabinet_equipment` + `maintenance_ticket`", PG, [],
      "Équipements du cabinet (fauteuil, autoclave, compresseur…, salle, fournisseur, technicien) et tickets de "
      "maintenance (priorité, statut, photos, intervention).",
      ["Aucune table ; autoclave référencé en texte dans la stérilisation"],
      ["Migration : `cabinet_equipment(id, cabinet_id, label, category, room, supplier, technician_email, technician_phone, purchased_at, next_check_at)` + `maintenance_ticket(id, cabinet_id, equipment_id?, title, description, priority, status, reported_by, assigned_to_email, created_at, resolved_at)` + `maintenance_ticket_photo(ticket_id, document_id)`", "RLS, pgTAP"],
      ["Migrations + pgTAP verts"],
      [RLS_REF, "`db/AGENTS.md`"])
issue("DP-F18.b", "[DP-F18.b] API — équipements, tickets, e-mail au technicien", RUST, ["DP-F18.a"],
      "CRUD équipements et tickets ; à la création d'un ticket, e-mail au technicien (Brevo si configuré, sinon no-op "
      "loggé) avec description et photos ; compteurs pour le dashboard (ouverts, planifiés, en retard).",
      ["`api/src/brevo_mailer.rs`, `api/src/documents.rs`"],
      ["`api/src/maintenance.rs`", "Tests"],
      ["CRUD + e-mail testés (mailer mocké)"],
      ["`api/src/brevo_mailer.rs`", "`api/src/documents.rs`", "`api/src/routes/misc.rs`"])
issue("DP-F18.c", "[DP-F18.c] Front secrétariat — écran « Maintenance » : équipements, tickets, photos", flutter(), ["DP-F18.b"],
      "Écran maintenance : compteurs, liste des tickets, création avec photo (caméra), fiche équipement.",
      ["Aucun écran"],
      ["Repository + écrans + capture photo", "Tests widget"],
      ["Ticket créé avec photo depuis le front"],
      ["`front/apps/app_secretariat/lib/features/stock/`", "`front/packages/nubia_design_system/`"])

# --- F19 Marge labo ------------------------------------------------------------------------------------------
issue("DP-F19.a", "[DP-F19.a] DB — `lab_price_list` (grille tarifaire par laboratoire)", PG, [],
      "Grille tarifaire des laboratoires (labo, libellé, code interne, prix) pour valoriser automatiquement le coût "
      "d'une commande et calculer la marge.",
      ["`lab_work_order.purchase_price_cents` existe (`db/migrations/0193_create_lab_work_order.sql`) mais est saisi à la main"],
      ["Migration : `lab_price_list(id, cabinet_id, lab_name, item_label, item_code, price_cents, valid_from)` + RLS + `lab_work_order.price_list_item_id?`", "pgTAP"],
      ["Migration + pgTAP verts"],
      ["`db/migrations/0193_create_lab_work_order.sql`"])
issue("DP-F19.b", "[DP-F19.b] API — grille labo (import CSV), valorisation auto, marge par acte / praticien, comparaison des labos", RUST, ["DP-F19.a"],
      "Import CSV de la grille, sélection d'un produit à la commande (prix pré-rempli), `GET /v1/cabinet/lab-stats?period=` : "
      "coût labo, CA patient, marge par acte, par praticien, par labo.",
      ["`api/src/lab_work_orders.rs`, `api/src/billing.rs`"],
      ["Endpoints + stats SQL", "Tests"],
      ["Marge calculée sur un jeu de test"],
      ["`api/src/lab_work_orders.rs`", "`api/src/cabinet_stats.rs`"])
issue("DP-F19.c", "[DP-F19.c] Front praticien — onglet « Labo » : produit de la grille, coût, marge ; stats labos", flutter(), ["DP-F19.b"],
      "Dans la commande labo : choix du produit de la grille (prix pré-rempli), affichage coût / CA / marge ; écran stats labos.",
      ["`front/apps/app_practicien/lib/features/lab_work/`"],
      ["Repository + UI", "Tests widget"],
      ["Marge visible sur une commande"],
      ["`front/apps/app_practicien/lib/features/lab_work/`"])

# --- F20 Dashboard personnalisable -----------------------------------------------------------------------------
issue("DP-F20.a", "[DP-F20.a] API — préférence de mise en page du dashboard par utilisateur", RUST, [],
      "`GET/PUT /v1/me/dashboard-layout` : liste ordonnée des widgets visibles (jsonb), par app et par rôle, avec valeurs par défaut.",
      ["Préférences existantes : `api/src/notifications.rs` (préférences de notification comme modèle)"],
      ["Migration légère `user_dashboard_layout(user_id, app, layout jsonb)`", "Endpoints + validation des identifiants de widgets", "Tests"],
      ["Endpoint testé"],
      ["`api/src/notifications.rs`", "`api/src/routes/notifications_devices.rs`"])
issue("DP-F20.b", "[DP-F20.b] Front — dashboard à widgets réordonnables / masquables (praticien, secrétariat)", flutter(), ["DP-F20.a", "DP-F1.b", "DP-F2.c"],
      "Registre de widgets (opportunités, tâches, prothèses, KPI, agenda du jour, notes…), bouton « Personnaliser » "
      "(afficher / masquer / réordonner), persistance via l'API.",
      ["Dashboards actuels figés : `front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`"],
      ["Registre + mode édition + persistance", "Tests widget"],
      ["Réordonnancement persistant entre deux sessions"],
      ["`front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`", "`front/apps/app_secretariat/lib/features/dashboard/`"])

# --- F21 Questionnaire paramétrable ------------------------------------------------------------------------------
issue("DP-F21.a", "[DP-F21.a] DB — `questionnaire_template` versionné (questionnaire médical paramétrable)", PG, [],
      "Modèles de questionnaire (schéma de questions en jsonb : type, libellé, options, logique conditionnelle, drapeau "
      "garde-fou) versionnés ; les soumissions référencent la version utilisée.",
      ["`db/migrations/0180_create_medical_questionnaire_submission.sql` : questionnaire fixe"],
      ["Migration : `questionnaire_template(id, cabinet_id NULL = standard, version, title, schema jsonb, is_active)` + `medical_questionnaire_submission.template_id/version` (nullable, backfill = standard v1)", "RLS, pgTAP, seed du questionnaire standard actuel en v1"],
      ["Migration + seed + pgTAP verts"],
      ["`db/migrations/0180_create_medical_questionnaire_submission.sql`"])
issue("DP-F21.b", "[DP-F21.b] API — CRUD des modèles de questionnaire + validation des réponses contre le schéma", RUST, ["DP-F21.a"],
      "Gérer les modèles, servir le schéma actif au patient, valider les soumissions contre le schéma (types, requis, "
      "logique), conserver les garde-fous existants (anticoagulant → alerte).",
      ["`api/src/medical_questionnaire.rs`, garde anticoagulant dans `api/src/consultation_act_create.rs`"],
      ["Endpoints + validateur de schéma", "Compatibilité ascendante avec les soumissions existantes", "Tests"],
      ["Soumission validée contre un modèle custom", "Garde-fous inchangés"],
      ["`api/src/medical_questionnaire.rs`", "`api/src/consultation_act_create.rs`"])
issue("DP-F21.c", "[DP-F21.c] Front — éditeur de questionnaire (praticien) + rendu dynamique (patient)", flutter(), ["DP-F21.b"],
      "Éditeur de questions (types, options, condition « afficher si »), aperçu ; côté patient, rendu dynamique du schéma actif.",
      ["`front/apps/app_patient/lib/features/medical_questionnaire/` (rendu fixe)"],
      ["Renderer dynamique partagé + éditeur", "Tests widget"],
      ["Questionnaire custom rempli de bout en bout"],
      ["`front/apps/app_patient/lib/features/medical_questionnaire/`", "`front/apps/app_practicien/lib/features/cabinet/`"])

# --- F22 Import de modèle DOCX ------------------------------------------------------------------------------------
issue("DP-F22.a", "[DP-F22.a] API — import d'un modèle DOCX avec placeholders, rendu via le moteur de courriers", RUST, ["DP-F7.a"],
      "Permettre au cabinet d'importer son propre modèle `.docx` contenant des placeholders `{{…}}`, le stocker comme "
      "`letter_template`, et le rendre (substitution dans le XML du document, conversion PDF si un convertisseur est disponible, sinon DOCX rendu).",
      ["Moteur : DP-F7.a", "Aucun import de modèle"],
      ["`POST /v1/letter-templates/import` (multipart docx) → extraction des placeholders, stockage", "Rendu DOCX par substitution XML (crate `docx-rs` ou zip+xml)", "Tests avec un docx d'exemple dans `api/tests/fixtures/`"],
      ["Docx importé, placeholders listés, rendu produit"],
      ["`api/src/letters.rs`", "`db/migrations/0167_create_letter_template.sql`"])
issue("DP-F22.b", "[DP-F22.b] Front praticien — importer un modèle DOCX dans les courriers types", flutter(), ["DP-F22.a"],
      "Bouton d'import dans l'écran des modèles de courrier, liste des placeholders détectés, test de rendu.",
      ["Écran courriers : DP-F7.b"],
      ["Upload + affichage + test", "Tests widget"],
      ["Import depuis le front"],
      ["`front/apps/app_practicien/lib/features/patients/`"])

# --- F23 CR opératoire structuré --------------------------------------------------------------------------------------
issue("DP-F23.a", "[DP-F23.a] DB — sections structurées sur `cr_template` (chirurgie, endo, paro)", PG, [],
      "Étendre les modèles de CR avec un schéma de sections structurées (jsonb) : patient & intervention, anesthésie, "
      "guide chirurgical, lambeau, implants (référence, lot), greffes, matériaux, post-opératoire, documents.",
      ["`db/migrations/0186_create_cr_template.sql` : modèles en texte libre"],
      ["Migration : `cr_template.sections jsonb` + `consultation_report.structured jsonb` (ou équivalent) ; seed de 3 modèles structurés (chirurgie implantaire, endo, paro)", "pgTAP"],
      ["Migration + seed + pgTAP verts"],
      ["`db/migrations/0186_create_cr_template.sql`"])
issue("DP-F23.b", "[DP-F23.b] API — CR structuré : sauvegarde brouillon auto, rendu texte + PDF, lien passeport implantaire", RUST, ["DP-F23.a"],
      "Enregistrer les sections structurées (brouillon à chaque frappe), rendre le CR en texte / PDF, et alimenter le "
      "passeport implantaire quand une section implant est remplie.",
      ["`api/src/cr_templates.rs`, `api/src/consultations.rs`, `api/src/implant_passport.rs`"],
      ["Endpoints + rendu + hook passeport", "Tests"],
      ["CR structuré sauvegardé et rendu", "Passeport implantaire alimenté"],
      ["`api/src/cr_templates.rs`", "`api/src/consultations.rs`", "`api/src/implant_passport.rs`"])
issue("DP-F23.c", "[DP-F23.c] Front praticien — formulaire de CR opératoire par sections (chirurgie, endo, paro)", flutter(), ["DP-F23.b"],
      "Formulaire à sections (navigation latérale), sauvegarde auto en brouillon, aperçu.",
      ["`front/apps/app_practicien/lib/features/consultation_clinique/`"],
      ["Renderer de sections + autosave + aperçu", "Tests widget"],
      ["CR complet saisi et rendu"],
      ["`front/apps/app_practicien/lib/features/consultation_clinique/`"])

# --- F24 Secrétariat : conversations qualifiées ----------------------------------------------------------------------
issue("DP-F24.a", "[DP-F24.a] DB — qualification des conversations cabinet (origine, motif, priorité, assigné, synthèse)", PG, [],
      "Ajouter à la conversation cabinet : `origin (phone|app|web|email|other)`, `motif`, `priority`, `assignee_user_id`, "
      "`summary`, `status (open|in_progress|done)`.",
      ["`db/migrations/0097_conversation_subject.sql` et suivantes"],
      ["Migration ALTER + index `(cabinet_id, status, priority)`", "pgTAP"],
      ["Migration + pgTAP verts"],
      ["`db/migrations/0097_conversation_subject.sql`"])
issue("DP-F24.b", "[DP-F24.b] API — inbox secrétariat : filtres, assignation, statut, synthèse", RUST, ["DP-F24.a"],
      "`GET /v1/cabinet/conversations?status=&priority=&assignee=&origin=` + PATCH de qualification ; la conversion d'une "
      "demande en RDV (`cabinet_conversation_convert.rs`) passe la conversation en `done`.",
      ["`api/src/cabinet_messaging.rs`, `api/src/cabinet_conversation_convert.rs`"],
      ["Filtres + PATCH + hook de conversion", "Tests"],
      ["Filtres et assignation testés"],
      ["`api/src/cabinet_messaging.rs`", "`api/src/cabinet_conversation_convert.rs`"])
issue("DP-F24.c", "[DP-F24.c] Front secrétariat — vue « Secrétariat » : conversations qualifiées, filtres, assignation", flutter(), ["DP-F24.b"],
      "Tableau des conversations ouvertes (statut, patient, origine, motif, synthèse, praticien, priorité, date), "
      "filtres rapides, assignation, passage en RDV.",
      ["`front/apps/app_secretariat/lib/features/cabinet_messaging/`"],
      ["Repository + tableau + filtres", "Tests widget"],
      ["Vue opérationnelle"],
      ["`front/apps/app_secretariat/lib/features/cabinet_messaging/`"])

# --- F25 Onboarding : liens d'invitation, signature/tampon ---------------------------------------------------------------
issue("DP-F25.a", "[DP-F25.a] DB — liens d'invitation par rôle + signature / tampon du praticien", PG, [],
      "`cabinet_invite_link(cabinet_id, role, token, expires_at, max_uses, uses)` et `provider.signature_image_id`, "
      "`provider.stamp_image_id` (documents).",
      ["`db/migrations/0021_app_user_invite.sql` : invitation nominative par e-mail"],
      ["Migrations + RLS", "pgTAP"],
      ["Migrations + pgTAP verts"],
      ["`db/migrations/0021_app_user_invite.sql`"])
issue("DP-F25.b", "[DP-F25.b] API — lien d'invitation copiable par rôle ; signature et tampon apposés sur les PDF", RUST, ["DP-F25.a", "DP-F7.a"],
      "`POST /v1/cabinet/invite-links {role}` → URL, `POST /v1/auth/register` accepte le token de lien ; upload de la "
      "signature et du tampon ; le moteur de courriers (DP-F7.a) et l'export de devis les apposent.",
      ["`api/src/auth/register.rs` (token nominatif), `api/src/cabinet_secretariats.rs`", "PDF : `api/src/letters.rs`, `api/src/cabinet_quotes_export.rs`"],
      ["Endpoints + apposition dans les PDF", "Tests"],
      ["Inscription via lien de rôle", "PDF avec signature/tampon"],
      ["`api/src/auth/register.rs`", "`api/src/cabinet_quotes_export.rs`"])
issue("DP-F25.c", "[DP-F25.c] Front secrétariat — onboarding : liens d'invitation par rôle, signature, tampon", flutter(), ["DP-F25.b"],
      "Dans l'onboarding et l'admin membres : boutons « copier le lien » par rôle (partage système), upload de signature "
      "et de tampon avec aperçu.",
      ["`front/apps/app_secretariat/lib/features/onboarding/`, `front/apps/app_secretariat/lib/features/admin_membres/`"],
      ["Repository + UI + partage", "Tests widget"],
      ["Lien copié, images uploadées"],
      ["`front/apps/app_secretariat/lib/features/onboarding/`", "`front/apps/app_secretariat/lib/features/admin_membres/`"])

# --- F26 Carte de visite QR ---------------------------------------------------------------------------------------------
issue("DP-F26.a", "[DP-F26.a] API + Front — carte de visite du cabinet avec QR (vCard)", RUST, [],
      "`GET /v1/cabinet/vcard` (vCard 4.0 + PNG du QR) et un bouton « Ma carte de visite » sur le dashboard praticien "
      "(partage / envoi au patient). Petit lot : l'API et un widget minimal ; l'agent Flutter reprendra le widget si besoin.",
      ["`api/src/cabinet_info.rs`"],
      ["Endpoint vCard + QR (crate `qrcode`)", "Tests"],
      ["vCard valide, QR lisible"],
      ["`api/src/cabinet_info.rs`", "`front/apps/app_practicien/lib/features/dashboard/dashboard_page.dart`"])

# --- F27 RH : planning, congés, pointeuse (priorité basse) -------------------------------------------------------------------
issue("DP-F27.a", "[DP-F27.a] DB — planning d'équipe, demandes de congés, pointage", PG, [],
      "`staff_shift(cabinet_id, user_id, starts_at, ends_at, room?)`, `leave_request(cabinet_id, user_id, from, to, kind, status, decided_by)`, "
      "`time_clock_entry(cabinet_id, user_id, clock_in, clock_out, source)`. Priorité basse (périmètre RH).",
      ["`provider_unavailability` couvre les absences praticien ; rien pour l'équipe"],
      ["Migrations + RLS", "pgTAP"],
      ["Migrations + pgTAP verts"],
      ["`api/src/provider_unavailability.rs`", RLS_REF])
issue("DP-F27.b", "[DP-F27.b] API — planning hebdo (PDF), congés (demande / validation), pointeuse par QR", RUST, ["DP-F27.a"],
      "CRUD des créneaux d'équipe, export PDF de la semaine, workflow de congé (demande → validation manager → "
      "indisponibilité), pointage par QR tournant (code renouvelé toutes les 60 s) ou saisie manuelle autorisée.",
      ["`api/src/provider_unavailability.rs`, `api/src/permissions.rs`"],
      ["`api/src/staff.rs`", "Tests"],
      ["Workflows testés"],
      ["`api/src/provider_unavailability.rs`", "`api/src/permissions.rs`"])
issue("DP-F27.c", "[DP-F27.c] Front — planning équipe, demande de congé, pointage (secrétariat + praticien)", flutter(), ["DP-F27.b"],
      "Écran planning semaine (secrétariat), demande de congé depuis le téléphone, validation manager, écran de pointage QR.",
      ["Aucun écran RH"],
      ["Repository + écrans", "Tests widget"],
      ["Parcours congé complet"],
      ["`front/apps/app_secretariat/lib/features/admin_membres/`", "`front/apps/app_practicien/lib/features/cabinet/`"])

# ---------------------------------------------------------------------------
# Rendu du body (contrat preflight.ts)
# ---------------------------------------------------------------------------

def slug(id_):
    return "agent/" + id_.lower().replace(".", "-")


def render_body(it, numbers):
    deps = it["deps"]
    if deps:
        dep_txt = ", ".join(f"#{numbers[d]}" if d in numbers else d for d in deps) + \
            " — attendre leur merge (promotion automatique par l'orchestrateur)."
    else:
        dep_txt = "— (fondation)"
    lines = ["## Objectif", it["objectif"], "",
             "## Dépend de", dep_txt, "",
             "## État actuel"] + [f"- {e}" for e in it["etat"]] + ["",
             "## Procédure"] + [f"{i + 1}. {p}" for i, p in enumerate(it["procedure"])] + ["",
             "## Done when"] + [f"- [ ] {d}" for d in it["done"]] + ["",
             "## Fichiers de référence (context-pack)"] + [f"- {f}" for f in it["files"]] + ["",
             "## Ref",
             f"Plan : {PLAN} §4 · Benchmark Dental Pilot · Branche : `{slug(it['id'])}`{it['extra_ref']}",
             "",
             "> Convention repo : commits en français à l'impératif, CI verte (build + tests + `test-integrity`), "
             "PR vers `main` avec `Closes #<issue>`. Lire `AGENTS.md` racine puis celui du dossier touché."]
    return "\n".join(lines)


REQUIRED = [r"^## Objectif$", r"^## (D[ée]pend de|Depend de)$", r"^## [EÉ]tat actuel$", r"^## Proc[ée]dure$",
            r"^## Done when$", r"^## Fichiers de r[ée]f[ée]rence", r"^## Ref$"]
PATH_RE = re.compile(r"`[a-z][a-z0-9_/.-]+\.(rs|dart|sql|ts|tsx|astro|yaml|md|toml|sh)`", re.I)


def check(body):
    missing = [r for r in REQUIRED if not re.search(r, body, re.M)]
    if not PATH_RE.search(body):
        missing.append("<path backtické>")
    return missing


# ---------------------------------------------------------------------------
# Forgejo
# ---------------------------------------------------------------------------

def repo_base():
    url = subprocess.check_output(["git", "remote", "get-url", "origin"], text=True).strip()
    m = re.match(r"(https?://[^/]+)/([^/]+)/([^/.]+)(\.git)?$", url)
    if not m:
        sys.exit(f"remote origin non reconnu : {url}")
    return m.group(1), f"{m.group(2)}/{m.group(3)}"


def api(base, token, path, method="GET", data=None):
    req = urllib.request.Request(base + "/api/v1" + path, method=method,
                                 headers={"Authorization": f"token {token}", "Content-Type": "application/json",
                                          "Accept": "application/json"},
                                 data=json.dumps(data).encode() if data is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            time.sleep(PACE)
            txt = r.read().decode()
            return json.loads(txt) if txt else None
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        raise SystemExit(f"{method} {path} → {e.code}: {body[:400]}")


def main():
    ids = [it["id"] for it in ISSUES]
    assert len(ids) == len(set(ids)), "ids dupliqués"
    for it in ISSUES:
        for d in it["deps"]:
            assert d in ids, f"{it['id']} dépend d'un id inconnu {d}"
    if DRY:
        bad = 0
        for it in ISSUES:
            m = check(render_body(it, {}))
            flag = "OK " if not m else "KO "
            bad += bool(m)
            print(f"{flag} {it['id']:9s} {it['assignee']:16s} deps={it['deps'] or '-'}  {it['title'][:70]}")
            if m:
                print("     manque :", m)
        roots = [it["id"] for it in ISSUES if not it["deps"] and it["id"] != "DP-F14.b"]
        print(f"\n{len(ISSUES)} issues, {len(roots)} racines (agent:go), {bad} body invalides")
        by = {}
        for it in ISSUES:
            by[it["assignee"]] = by.get(it["assignee"], 0) + 1
        print("par agent :", by)
        return

    token = os.environ.get("FORGEJO_TOKEN")
    if not token:
        sys.exit("FORGEJO_TOKEN manquant")
    base, repo = repo_base()
    print(f"Forgejo {base} · dépôt {repo}")

    # labels
    labels = {l["name"]: l["id"] for l in api(base, token, f"/repos/{repo}/labels?limit=200")}
    if "agent:go" not in labels:
        sys.exit("label agent:go introuvable — le créer d'abord")
    if "benchmark:dental-pilot" not in labels:
        l = api(base, token, f"/repos/{repo}/labels", "POST",
                {"name": "benchmark:dental-pilot", "color": "#1f6f5c", "description": "Parité Dental Pilot (docs/17)"})
        labels["benchmark:dental-pilot"] = l["id"]

    # idempotence : issues ouvertes existantes par préfixe de titre
    existing = {}
    page = 1
    while True:
        chunk = api(base, token, f"/repos/{repo}/issues?state=open&type=issues&limit=50&page={page}")
        if not chunk:
            break
        for i in chunk:
            m = re.match(r"\[(DP-F\d+\.[a-z])\]", i["title"])
            if m:
                existing[m.group(1)] = i["number"]
        page += 1
    if existing:
        print(f"{len(existing)} issues déjà présentes, non recréées : {sorted(existing)}")

    numbers = dict(existing)
    # 1. création (bodies avec placeholders)
    for it in ISSUES:
        if it["id"] in numbers:
            continue
        body = render_body(it, {})
        assert not check(body), (it["id"], check(body))
        created = api(base, token, f"/repos/{repo}/issues", "POST",
                      {"title": it["title"], "body": body, "assignees": [it["assignee"]],
                       "labels": [labels["benchmark:dental-pilot"]]})
        numbers[it["id"]] = created["number"]
        print(f"créée #{created['number']}  {it['id']}  → {it['assignee']}")

    # 2. bodies définitifs (numéros réels) + dépendances natives
    for it in ISSUES:
        n = numbers[it["id"]]
        if it["deps"]:
            api(base, token, f"/repos/{repo}/issues/{n}", "PATCH", {"body": render_body(it, numbers)})
            for d in it["deps"]:
                api(base, token, f"/repos/{repo}/issues/{n}/dependencies", "POST",
                    {"index": numbers[d], "owner": repo.split("/")[0], "repo": repo.split("/")[1]})

    # 3. épic
    if "DP-EPIC" not in existing:
        rows = "\n".join(f"- #{numbers[it['id']]} `{it['id']}` {it['title'].split('] ', 1)[1]} — `{it['assignee']}`" for it in ISSUES)
        api(base, token, f"/repos/{repo}/issues", "POST", {
            "title": "[DP-EPIC] Parité fonctionnelle Dental Pilot — benchmark docs/17",
            "labels": [labels["benchmark:dental-pilot"]],
            "body": "## Objectif\nAtteindre la parité sur les manques identifiés dans `docs/17-benchmark-dental-pilot.md` "
                    "§4.1 et §4.2 (le §4.3 lourd / externe est exclu).\n\n## Dépend de\n— (épic)\n\n## État actuel\n"
                    "Voir le benchmark.\n\n## Procédure\nSuivre les issues ci-dessous, chaînées par dépendances.\n\n"
                    "## Done when\n- [ ] toutes les issues ci-dessous sont fermées\n\n"
                    "## Fichiers de référence (context-pack)\n- `docs/17-benchmark-dental-pilot.md`\n\n## Ref\n"
                    "Plan : `docs/17-benchmark-dental-pilot.md`\n\n## Issues\n" + rows})

    # 4. agent:go sur les racines (en dernier : déclenche le dispatch)
    for it in ISSUES:
        if it["deps"] or it["id"] == "DP-F14.b" or it["id"] in existing:
            continue
        api(base, token, f"/repos/{repo}/issues/{numbers[it['id']]}/labels", "POST", {"labels": [labels["agent:go"]]})
        print(f"agent:go → #{numbers[it['id']]} {it['id']}")

    out = os.path.join(os.path.dirname(__file__), "..", "docs", "ateliers", "dp-benchmark-issues.json")
    with open(out, "w") as f:
        json.dump(numbers, f, indent=2, sort_keys=True)
    print(f"\n{len(numbers)} issues · mapping écrit dans {os.path.relpath(out)}")


if __name__ == "__main__":
    main()
