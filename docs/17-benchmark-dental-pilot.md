# 17 — Benchmark : Dental Pilot vs Nubia

> Comparatif fonctionnel entre **Dental Pilot** (Dr Raphaël Adad, démo vidéo de
> 38 min, septembre 2026) et l'état réel de Nubia au 2026-09-16. Objectif :
> savoir ce qu'ils ont que nous n'avons pas, ce que nous avons qu'ils n'ont
> pas, et ce qu'il faut faire pour atteindre leur niveau puis faire mieux.
>
> Source : `~/dev/private/scrapper/videoCut/out/video/` — transcription en 62
> segments + une image par segment. Côté Nubia, chaque ligne est vérifiée dans
> `api/src`, `db/migrations`, `front/apps` — pas supposée.

## 0. Ce que ce benchmark n'est pas

- Une démo commerciale montre ce qui marche ; elle ne montre ni la robustesse,
  ni ce qui est réellement livré chez un client. Plusieurs fonctions de la vidéo
  sont annoncées « bientôt » (version locale, interop Doctolib, Google Agenda,
  suivi des congés, financement, iTero, app patient) — elles sont marquées 🔜.
- La qualité visuelle de Dental Pilot est nettement au-dessus de la nôtre
  (frein n°4 du CR du 08/09). Ce document compare les **fonctions**, pas le
  design — mais le design reste le premier frein à la vente.

## 1. Dental Pilot en une page

| | |
|---|---|
| Positionnement | « Votre cabinet, enfin sur pilote automatique » — logiciel métier dentaire + ortho, cloud, Mac/PC/tablette/téléphone, version locale 🔜 |
| Cibles affichées | Dentistes, orthodontistes, cabinets multi-utilisateurs ; mode « full ortho » qui masque les onglets inutiles |
| Modèle | Abonnement (montant non montré) + onboarding 390 € (« le double après fin d'année ») + **crédits IA** consommés par fonction (460 inclus / mois dans le plan montré) |
| Migration | Logos « en quelques minutes », DSIO (format standard), CSV/Excel Doctolib, connecteurs à la demande |
| Signature | L'**IA partout** : devis par mots-clés, plan de traitement dicté, découpage des séances, analyse de panoramique, dictée des CR, secrétariat vocal, inbox e-mail, support, analyse des retours FSE |
| Périmètre inhabituel | Gestion de cabinet étendue : RH (planning, congés, pointeuse), maintenance des équipements, conformité et veille réglementaire, BI avec connexion bancaire, recouvrement |
| Écosystème | 3Shape / MEDIT / Shining (iTero 🔜), Doctolib 🔜, Google Agenda 🔜, Google Business Profile, Silae 🔜 |

**Lecture** : Dental Pilot est un logiciel de gestion **du cabinet** vu par un
praticien-gérant, avec l'IA comme argument central et monétisé. Nubia est une
plateforme **patient + cabinet + pharmacie + infirmière**, multi-profession,
avec la conformité et la sécurité comme socle. Les deux se recouvrent sur le
cœur métier dentaire ; ils ne visent pas la même promesse.

## 2. Matrice par domaine

Légende : ✅ vu / vérifié · 🟠 partiel · ⛔ absent · 🔜 annoncé, pas montré.
Colonne « Écart » : **DP+** Dental Pilot devant · **N+** Nubia devant · **=** équivalent.

### 2.1 Onboarding et migration

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Parcours de démarrage guidé (5 étapes, barre de progression) | ✅ | 🟠 `app_secretariat/onboarding` | DP+ |
| Invitation des membres par lien, par rôle (WhatsApp / e-mail) | ✅ | 🟠 `POST /v1/cabinet/members` + token par e-mail (0021) ; pas de lien copiable par rôle | DP+ |
| Migration Logos automatique | ✅ | ⛔ | DP+ |
| Import DSIO / CSV Doctolib | ✅ | ⛔ `data_import_job` (0168) = **table de suivi seulement**, aucun parseur | DP+ |
| Signature et tampon du praticien apposés sur tous les documents | ✅ | ⛔ | DP+ |
| Onboarding accompagné payant | ✅ 390 € | — (modèle à définir) | — |

### 2.2 Tableau de bord et pilotage quotidien

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Dashboard personnalisable par rôle (widgets) | ✅ | 🟠 dashboards fixes praticien / secrétariat | DP+ |
| KPI : CA année, RDV du jour, rappels en attente, taux d'occupation | ✅ | 🟠 `cabinet_stats`, `dashboard.rs` — pas de taux d'occupation ni d'objectif | DP+ |
| « Opportunités du moment » : devis sans réponse > 7 j, devis acceptés sans RDV, factures impayées > 30 j, patients sans prochain RDV | ✅ | 🟠 les données existent (`quote_relances`, `patient_alerts` avec `OVERDUE_INVOICE_DELAY_DAYS = 30`, `recall_campaigns`) — pas la vue agrégée | DP+ (faible effort) |
| Tâches à réaliser, assignables à un membre, notifiées | ✅ | ⛔ — lot 2 « to-do secrétariat » | DP+ |
| Prothèses du jour | ✅ | ⛔ (`lab_work_orders` sans date de pose) | DP+ |
| Événements à venir (congés, formations, absences) | ✅ | 🟠 `provider_unavailability` | DP+ |
| Anniversaires patients | ✅ | ⛔ | DP+ |
| Patients du jour : en salle d'attente / en consultation / vus | ✅ | ✅ `waiting_room` praticien + secrétariat, check-in QR / app / manuel | = |
| Bouton « Carte Vitale » / « Télétransmission » sur toutes les pages | ✅ | ⛔ | DP+ (dépend de Q-01) |

### 2.3 Fiche patient et schéma dentaire

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Fiche patient : identité, couverture sociale, mutuelle | ✅ | ✅ + période de couverture, référentiel mutuelles (0187) | = |
| Questionnaire médical avec garde-fous | ✅ | ✅ + revue cabinet (0180, 0199), garde anticoagulant à la cotation | N+ |
| Schéma dentaire adulte / enfant, vue large ou latérale | ✅ (dents réalistes) | 🟠 `dental_chart` — « fait Galaxy » (frein n°4) | DP+ (design) |
| Charting parodontal | ✅ BOP, plaque, poches, mobilité, arcade par arcade | ✅ `periodontal_chart.rs` | = |
| Module ortho, endo, chirurgie | ✅ modes dédiés | 🟠 `orthodontics.rs`, pas d'endo | DP+ |
| Actes favoris | ✅ | ✅ `practitioner_favorite_acts` | = |
| Groupements d'actes | ✅ | ✅ `ccam_act_bundle` (0182) | = |
| Catégories d'actes activables par cabinet | ✅ | ⛔ | DP+ |
| Actes « à faire » / « réalisés » avec dents, cotation, tarif, colonnes D-C-R-F-L | ✅ | ✅ `consultation_acts` avec statut, tarif OPTAM auto | = |
| Notes patient, historique | ✅ | ✅ `medical_record`, `patient_tags`, `patient_alerts` | = |
| Galerie / imagerie | ✅ onglet | 🟠 `documents` | DP+ |
| Fusion de doublons patients, tutelle / proches | — | ✅ `patient_merge`, `patient_guardianship`, `dependents` | N+ |

### 2.4 Cotation

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Catalogue CCAM / NGAP complet | ✅ (recherche, code, tarif, base) | 🟠 catalogue incomplet, `panier_sante` NULL partout — **lot 1** | DP+ |
| Recherche d'acte par libellé | ✅ | ✅ | = |
| Devis généré par mots-clés (IA) | ✅ « couronne 16, composite 26 » → devis | ⛔ | DP+ |
| Règles **bloquantes** à la saisie : incompatibilités, cumul, anticoagulant, groupes, stock | non montré | ✅ `consultation_act_create.rs` (422 / 409) | **N+** |
| Paniers 100 % Santé, plafonds opposables, cohérence de panier | non montré | 🟠 lot 1 | ? |
| Vérification formelle des règles (TLA+) | — | 🔜 D-08 | N+ (à livrer) |

### 2.5 Imagerie et IA clinique

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Analyse de panoramique par IA : segmentation, pathologies, traitements recommandés par dent, indice de confiance | ✅ | ⛔ — lot 8, partenariat Allisone évoqué | DP+ |
| Import radio dans le bilan | ✅ | 🟠 `documents` | DP+ |
| Suggestions IA reprises dans le plan de traitement | ✅ | ⛔ | DP+ |

> Garde-fou `docs/03` §2 et `docs/07` §8 : une IA qui *recommande un
> traitement* par dent flirte avec le dispositif médical (MDR). Dental Pilot
> l'assume. Nous avons décidé de ne pas y aller au MVP. À garder en tête avant
> de vouloir « faire pareil ».

### 2.6 Plan de traitement et séances

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Plan de traitement par séances | ✅ | ✅ `treatment_phases`, `treatment_plans` (côté patient aussi) | = |
| Plan dicté / saisi en langage naturel → actes (IA) | ✅ | ⛔ | DP+ |
| Découpage automatique des séances après signature (paramétrable : pas mélanger maxillaire/mandibulaire, regrouper par secteur, 60 min max…) | ✅ | ⛔ | DP+ |
| Placement des séances dans l'agenda depuis le plan, créneaux proposés | ✅ | 🟠 agenda + verrou 10 min, pas de lien plan → créneaux | DP+ |
| Plan converti en devis | ✅ | ✅ | = |

### 2.7 Devis, signature, acompte

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Devis depuis les actes, tarifs modifiables, RAC affiché | ✅ | ✅ `cabinet_quotes`, `quote_item_parts` | = |
| Historique / journal du devis (consulté, signé, échanges) | ✅ | 🟠 statuts + `audit_log` | DP+ |
| Envoi par e-mail avec pièces à joindre : consentements par type d'acte, ordonnance, courrier ; lien patient ; message personnalisable | ✅ | 🟠 envoi + relance J+3 / J+7 ; pas de pièces jointes sélectionnables | DP+ |
| Attestation d'information signée | ✅ | ⛔ | DP+ |
| Signature électronique | ✅ (sur place ou à distance, interface aux couleurs du cabinet) | ✅ Yousign + `/sign` app patient | = |
| Acompte à la signature | 🟠 « le patient paie un acompte » en option d'envoi | ✅ taux d'acompte, expiration, Stripe / GoCardless (stubs) | N+ |
| Demande d'estimation de prise en charge mutuelle | ✅ « en cours de travail » | ⛔ — module d'Abir (Q-04) | DP+ 🔜 |
| Suivi devis cabinet : tous statuts, tous praticiens, dashboard de performance | ✅ | 🟠 `cabinet_quotes_export`, `devis` secrétariat | DP+ |
| Refus de devis motivé | — | ⛔ lot 3 | — |
| Export / impression PDF | ✅ | ✅ | = |

### 2.8 Interface patient

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Espace patient web relié au cabinet : voir le devis, poser une question, signer, documents à lire avant le RDV | ✅ | ✅ | = |
| App patient native | 🔜 | ✅ `app_patient`, 30 features | **N+** |
| Prise de RDV, série, annulation, rappels, check-in QR | ✅ / 🟠 | ✅ | N+ |
| Proches / enfants, tutelle | — | ✅ `dependents`, `guardianship` | N+ |
| Ordonnances, envoi à la pharmacie, commandes et devis pharmacie | — | ✅ `prescriptions`, `pharmacy_orders`, `pharmacy_quotes` | N+ |
| Passeport implantaire patient | — | ✅ `implant_passport` | N+ |
| Questionnaire médical avant le RDV, consentements | ✅ | ✅ | = |
| Plans de traitement, financier (échéancier), avis, soins à domicile | — | ✅ | N+ |
| Messagerie patient ↔ cabinet | ✅ (via devis / e-mail) | ✅ conversations | = |

### 2.9 Comptes rendus, courriers, documents

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| CR de consultation avec modèles | ✅ | ✅ `cr_templates` (0186) | = |
| CR opératoire structuré (anesthésie, guide, lambeau, implants, greffes, post-op) | ✅ | 🟠 modèles libres | DP+ |
| Dictée vocale (PC ou téléphone via QR) → CR, plan, paro | ✅ (crédits IA) | ⛔ — lot 8, D-10 | DP+ |
| Courriers types avec en-tête / pied standardisés, logo | ✅ | 🟠 `letter_template` (0167) — schéma seul, **moteur de substitution non fait** | DP+ |
| Correspondants : carnet, mention dans le courrier, envoi, suivi des patients adressés et du CA apporté | ✅ | 🟠 `patient_correspondent` (0176), `referring_doctor` — pas de suivi CA ni d'envoi | DP+ |
| Bibliothèque de consentements éclairés par type d'acte | ✅ (10+ modèles) | ⛔ `consent_record` trace le consentement, aucune bibliothèque | DP+ |
| Import d'un modèle Word / PDF avec champs à remplir | ✅ | ⛔ | DP+ |
| Ordonnances types | ✅ | ✅ `prescription_template` (catalogue partagé), renouvellement, envoi pharmacie | N+ |
| Drive par membre d'équipe, connexion Google Drive | ✅ | ⛔ | DP+ |
| Génération de document par la voix | ✅ | ⛔ | DP+ |

### 2.10 Facturation, FSE, paiements

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Facture depuis les actes réalisés | ✅ | ✅ `billing.rs` | = |
| FSE / télétransmission | ✅ bouton partout, « retours FSE analysés par IA » 🔜 | ⛔ Q-01, lot 7 | DP+ |
| Paiement total / partiel / échelonné, rappels | ✅ | ✅ `payment_schedules`, `billing_payments` | = |
| Relance d'un impayé au patient | ✅ | 🟠 alerte `patient_alerts` ; pas d'envoi | DP+ |
| Encaissement manuel, clôture de caisse, bordereau de remise en banque | — | ✅ `cabinet_cash_register`, `bank_deposit_slip` | **N+** |
| Paiement en ligne (Stripe / GoCardless), terminal CB | 🟠 | 🟠 stubs, `docs/14` | = |
| Tiers payant réel | non montré | ⛔ déclaratif 70 % | ? |
| Module rejets (CA facturé / encaissé / rejeté, par caisse) | 🟠 « retours FSE » 🔜 | ⛔ module d'Abir | — |
| Recouvrement : dossier transmis à un organisme | ✅ | ⛔ | DP+ |

### 2.11 Prothèses et laboratoire

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Commandes de travaux labo par patient | ✅ | ✅ `lab_work_orders` (0193), `lab_work` praticien | = |
| Connexion 3Shape / MEDIT / Shining, cas et STL récupérés automatiquement | ✅ | ⛔ | DP+ |
| Chat avec le labo sans compte (par e-mail), envoi de fichiers | ✅ | ⛔ | DP+ |
| Grille tarifaire labo importée, coût / CA / **marge par acte** | ✅ | ⛔ | DP+ |
| Statut d'expédition, alerte « prothèse non livrée la veille » | 🟠 « prothèses du jour » | ⛔ lot 5 | DP+ |

### 2.12 Agenda et prise de rendez-vous

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Agenda multi-praticiens, filtres, motifs, statuts | ✅ | ✅ `scheduling`, `appointment_motifs`, séries | = |
| Liste d'attente (pré-RDV depuis le site), avancer / confirmer / retirer | ✅ | ✅ `bookings.rs`, `waiting_list` secrétariat | = |
| Widget de prise de RDV en ligne à intégrer sur le site du cabinet ; réservation instantanée ou sur demande | ✅ | ✅ site public `web_tunnel` (reservation.doc.nubia-link.com) + marketplace | N+ |
| Interop Doctolib | 🔜 | 🟠 FHIR R4 + HL7v2 MLLP (chantier 13/19 lots) | N+ |
| Google Agenda | 🔜 | ⛔ | — |
| Note / tâche à l'assistante lors de la prise de RDV (« prépare le guide ») | ✅ | ⛔ | DP+ |
| Déplacer un RDV → e-mail de confirmation avec QR | ✅ | ✅ notification + QR check-in | = |
| Briefs de la journée / semaine / prothèses à poser | ✅ | ⛔ | DP+ |

### 2.13 Rappels et communication patient

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Rappels e-mail / SMS | ✅ | ✅ Brevo / Twilio + push FCM | = |
| WhatsApp | ✅ | ⛔ | DP+ |
| Réponse présent / absent qui libère le créneau | non montré | ⛔ lot 2 | ? |
| Rappels cliniques (X mois sans RDV, détartrage) | 🟠 « patients sans prochain RDV » | ✅ `recall_campaigns` | N+ |
| Notification patient sur créneau libéré | — | ⛔ lot 2 | — |

### 2.14 Secrétariat et boîte de réception

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Vue secrétariat : conversations par origine (tél, IA, site), motif, synthèse, priorité, assignation | ✅ | 🟠 `cabinet_messaging`, `cabinet_conversation_convert` | DP+ |
| **Secrétaire IA vocale** qui prend les RDV au téléphone | ✅ (option) | ⛔ — D-03 / lot 8 : « l'accueil doit rester humain » | DP+ (choix assumé) |
| Inbox e-mail du cabinet connectée (Gmail), tâches et réponses suggérées par IA | ✅ | ⛔ | DP+ |
| Messagerie interne praticien ↔ secrétariat | — | ✅ `cabinet_team_messages` | N+ |
| Messagerie pharmacie, support | — | ✅ | N+ |

### 2.15 Stock et fournisseurs

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Stock principal + stock par salle, catégories, seuils d'alerte | ✅ | ✅ `stock_items`, `stock_inventory` (0192) — pas de stock par salle | 🟠 = |
| Décrément automatique par acte CCAM | non montré | ✅ `ccam_stock_mappings`, `consultation_act_stock` | **N+** |
| Code-barres / scan | 🟠 | ✅ | N+ |
| Fournisseurs (compte client, commercial), **bon de commande envoyé au fournisseur** | ✅ | ⛔ — `stock_request` = demande cabinet → pharmacie, pas fournisseur | DP+ |
| Import du stock depuis une facture | ✅ | ⛔ | DP+ |

### 2.16 Stérilisation et traçabilité

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Cycles d'autoclave, kits, traçabilité par patient | ✅ | ✅ cycles, sachets, numéro d'autoclave (0190 → 0202) | = |
| Étiquettes générées, scan par téléphone ou webcam sans douchette | ✅ | ⛔ | DP+ |
| Test Bowie-Dick, photos du dossier, dispositifs rattachés | ✅ | 🟠 | DP+ |
| Traçabilité implants ; scan du **Data Matrix** depuis le catalogue fournisseur | ✅ | 🟠 `implant_passport` (côté patient), pas de scan | DP+ |
| Déclaration DMSM (dispositif médical sur mesure) par patient, générée | ✅ | ⛔ | DP+ |

### 2.17 Conformité, registres, maintenance

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Registres obligatoires, données personnelles, DM ; génération documentaire ; **veille réglementaire** | ✅ | ⛔ — lot 4 (grille ARS d'Abir, A-02) | DP+ |
| Maintenance : équipements référencés, tickets au technicien sans compte, photos | ✅ | ⛔ | DP+ |
| Audit append-only, journal consultable | non montré | ✅ `audit_log` + écran secrétariat | N+ |

### 2.18 Équipe, RH, droits

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Membres, rôles, gestion des droits fine | ✅ | ✅ `permissions.rs`, rôles manager / doctor / secretary, secrétariats externes | = |
| Planning des équipes, PDF | ✅ | ⛔ | DP+ |
| Demandes de congés depuis le téléphone, suivi congés / RTT, Silae 🔜 | ✅ / 🔜 | ⛔ | DP+ |
| Pointeuse par QR, saisie manuelle des heures | ✅ | ⛔ | DP+ |
| Contrats, anniversaires | ✅ | ⛔ | DP+ |
| Double authentification | ✅ SMS | ✅ TOTP (`auth/mfa_*`) | = |

### 2.19 Business intelligence et finance

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Dashboard BI : CA produit / encaissé / à encaisser, nouveaux patients, évolution, alertes financières | ✅ | 🟠 `cabinet_stats`, `cabinet_payouts` | DP+ |
| Objectifs par dentiste et par mois, CA encaissé vs envisagé | ✅ | ⛔ — lot 2 « tableau de bord praticien » | DP+ |
| Performance par acte (rémunérateur ou non) | ✅ | ⛔ | DP+ |
| Frais labo : coût / CA / marge par praticien, comparaison des labos | ✅ | ⛔ | DP+ |
| Export réglementaire actes réalisés vs facturés (contrôle Sécu) | ✅ | ⛔ | DP+ |
| **Connexion bancaire** (agrégateur), trésorerie temps réel, rapprochement Sécu / tiers payant | ✅ / 🔜 | ⛔ | DP+ |
| Recouvrement, financement 🔜 | ✅ / 🔜 | ⛔ | DP+ |
| Satisfaction patient, avis | — | ✅ `patient_satisfaction`, `reviews` | N+ |

### 2.20 Support, paramètres, IA

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Support : ticket, IA entraînée sur les notices, escalade humain, prise en main à distance, captures / vocaux | ✅ | 🟠 `support.rs` (humain) | DP+ |
| Carte de visite du cabinet avec QR | ✅ | ⛔ | DP+ |
| E-réputation Google Business Profile | ✅ (« bientôt » côté demande d'avis) | ⛔ | DP+ |
| Préférences : logo praticien ≠ cabinet, couleurs, règles de rédaction | ✅ | 🟠 | DP+ |
| Comportements automatiques : quels documents partent avec quel devis, planification auto | ✅ | ⛔ | DP+ |
| **Crédits IA** : estimation par fonction, consommation suivie | ✅ | — pas d'IA, D-03 : jamais imposée, local ou cloud au choix | N+ (positionnement) |
| Analytics produit | non montré | ✅ PostHog (à couper sur la box) | — |

### 2.21 Plateforme, sécurité, déploiement

| Fonction | Dental Pilot | Nubia | Écart |
|---|---|---|---|
| Cloud, multi-device | ✅ | ✅ 5 fronts Flutter web + mobile | = |
| Version locale / sans internet | 🔜 | 🔜 box LAN (socle 1, ~70 % via `infra/deploy`) | = 🔜 |
| Isolation multi-tenant (RLS), chiffrement colonne, audit append-only | non montré | ✅ dès le départ | N+ (à démontrer) |
| HDS | non montré | ⛔ | ? |
| Multi-profession (infirmière, pharmacie, marketplace toutes spécialités) | ⛔ | ✅ | **N+** |
| Interop standard (FHIR R4, HL7v2) | ⛔ | ✅ | N+ |

## 3. Ce que Nubia a et que Dental Pilot ne montre pas

1. **L'écosystème patient** : app native complète, proches et tutelle,
   ordonnances → pharmacie (commandes, devis, retrait), passeport implantaire,
   plans de traitement et échéancier côté patient. Dental Pilot n'a qu'un
   espace web lié au devis et annonce l'app.
2. **Le moteur de règles bloquantes à la cotation** (incompatibilités, cumul,
   anticoagulant, OPTAM, stock). Dental Pilot *suggère* par IA ; nous
   *interdisons* par règle — et nous allons le prouver (TLA+, D-08). C'est
   l'argument d'Abir : « un acte mal coté ne doit pas pouvoir être saisi ».
3. **Caisse et trésorerie du cabinet** : clôture de caisse, bordereaux de
   remise en banque, encaissement manuel.
4. **Stock relié aux actes** : décrément automatique par acte CCAM,
   code-barres.
5. **Sécurité et conformité by design** : RLS multi-tenant, chiffrement colonne,
   audit append-only consultable, TOTP. Invisible en démo, décisif en
   contrôle.
6. **Multi-profession et marketplace** : pharmacie, infirmière, site public de
   réservation, recherche toutes spécialités, téléconsultation (docs).
7. **Interop standard** FHIR R4 + HL7v2 — là où Dental Pilot annonce
   « interopérabilité Doctolib » sans la montrer.
8. **Messagerie interne** praticien ↔ secrétariat, pharmacie, support.
9. **Rappels cliniques** par campagne (X mois sans RDV, détartrage).
10. **Pas d'IA imposée, pas de crédits** — un positionnement, pas une fonction,
    mais il se vend (D-03, contrecoup Doctolib).

## 4. Ce que Dental Pilot a et que nous n'avons pas

Groupé par effort, chaque ligne rattachée au lot de la roadmap du 16/09 quand
il existe. **S** = jours, **M** = semaines, **L** = mois ou dépendance externe.

### 4.1 Faible effort — les briques existent, il manque l'écran ou la règle

| Manque | Effort | Sur quoi ça s'appuie | Lot |
|---|---|---|---|
| Vue « opportunités » : devis sans réponse, acceptés sans RDV, impayés > 30 j, patients sans prochain RDV | S | `quote_relances`, `patient_alerts`, `recall_campaigns` | Socle 3 |
| Tâches assignables et notifiées (dont note à l'assistante depuis un RDV) | S-M | `notifications`, `cabinet_team_messages` | Socle 3 (to-do) |
| Prothèses du jour / alerte prothèse non reçue | S | `lab_work_orders` + date de pose | Lot 5 |
| Relance d'impayé envoyée au patient | S | `patient_alerts` + `reminders` | Socle 4 |
| Envoi de devis avec pièces à joindre (consentement, ordonnance, courrier) | S-M | `cabinet_quotes`, `documents` | Socle 4 |
| Moteur de substitution des courriers types (`{{patient.prenom}}`) + en-tête / pied cabinet | S-M | `letter_template` (schéma prêt) | Socle 3 |
| Bibliothèque de consentements éclairés par type d'acte | S | `consent_record`, `cr_templates` comme modèle | Socle 4 |
| Attestation d'information signée | S | flux de signature existant | Socle 4 |
| Briefs journée / semaine / prothèses | S | agenda + lab orders | Socle 3 |
| Objectifs par praticien, taux d'occupation, CA du jour / mois / centre | S-M | `cabinet_stats` | Socle 3 (dashboard) |
| Catégories d'actes activables par cabinet, mode « full ortho » | S | catalogue | Socle 2 |
| Stock par salle, import depuis facture | S | `stock_inventory` | — |
| Étiquettes de stérilisation + scan webcam / téléphone | S-M | sachets tracés (0191) | Lot 4 |
| Carte de visite QR, anniversaires | S | — | — |

### 4.2 Effort moyen — nouveau module sur base existante

| Manque | Effort | Lot | Note |
|---|---|---|---|
| **Reprise de données** Logos / DSIO / CSV Doctolib | M | **Socle 1 — critique pour le pilote** | Rien n'existe. DSIO est le format d'échange standard des logiciels dentaires français : c'est le connecteur à faire en premier, il couvre Logos, Desmos, Veasy… |
| Correspondants côté cabinet : carnet, courrier, envoi, suivi des adressages et du CA | M | Socle 3 | `patient_correspondent` (0176) comme point de départ |
| Fournisseurs + bon de commande envoyé par e-mail | M | — | |
| Planification des séances depuis le plan de traitement → créneaux agenda | M | Socle 3 | Sans IA : règles paramétrables (secteur, durée, regroupement) font 80 % du travail |
| Découpage de séances automatique après signature | M | Socle 3 | Idem, règles |
| Journal du devis (consulté / signé / échanges) | M | Socle 4 | `audit_log` |
| Conformité : registres, DM, DMSM, veille réglementaire | M | **Lot 4** | Grille ARS d'Abir (A-02) — Dental Pilot y est déjà, attention |
| Maintenance équipements + tickets technicien sans compte | M | Lot 4 | |
| Marge labo : grille tarifaire, coût / CA / marge par acte, comparaison labos | M | Lot 5 | |
| Suivi devis cabinet multi-praticiens avec performance | M | Socle 4 | |
| Dashboard personnalisable par rôle | M | Socle 3 | |
| Questionnaire médical paramétrable (builder) | M | — | Aujourd'hui questionnaire fixe |
| Import de modèle Word / PDF avec champs | M | — | |
| CR opératoire structuré (chirurgie, endo, paro) | M | Socle 3 | |
| Planning d'équipe, congés, pointeuse | M | hors dentaire pur | Question de périmètre : est-ce à nous de faire de la RH ? |
| Secrétariat : vue conversations par origine / motif / priorité / assignation | M | Socle 3 | |

### 4.3 Lourd ou dépendance externe

| Manque | Effort | Lot | Note |
|---|---|---|---|
| FSE / télétransmission, retours NOÉMIE | L | Lot 7, Q-01 | Dental Pilot l'a. Sans ça on ne remplace pas Logos non plus |
| Connexion 3Shape / MEDIT / Shining, STL | L | Lot 5 | API constructeurs |
| Connexion bancaire, rapprochement, recouvrement, financement | L | post-pilote | Agrégateur DSP2 + partenaires |
| WhatsApp, Google Agenda, Google Business Profile, Gmail | L | — | APIs tierces, chacune un chantier ; incompatibles avec la box LAN (D-06) |
| Analyse de panoramique par IA | L | Lot 8 | Allisone ; risque MDR (`docs/07` §8) |
| Dictée vocale → CR / plan / paro | L | Lot 8, D-10 | LLM local, matériel |
| Devis et plan par langage naturel | L | Lot 8 | Un mapping libellé → CCAM par recherche fait déjà l'essentiel sans LLM |
| Secrétaire IA vocale, inbox IA, support IA | L | Lot 8 | Non prioritaire par décision (accueil humain) |

## 5. Plan : même niveau, puis mieux

### 5.1 Où se joue la parité

Sur le **cœur du quotidien dentaire** — fiche, schéma, actes, devis, séances,
facture, labo, stérilisation, agenda — nous sommes à parité ou proches sur les
données, et en retard sur trois choses : **la reprise de données**, **les
enchaînements** (opportunités → tâches → notification ; plan → séances →
agenda ; devis → pièces jointes → attestation → signature) et **le design**.
Les enchaînements sont du §4.1 : semaines, pas mois. La reprise de données est
le seul manque qui bloque le pilote lui-même.

Sur la **gestion de cabinet étendue** (RH, maintenance, banque, recouvrement),
Dental Pilot est seul. C'est un choix de périmètre à faire, pas un retard :
la conformité et la maintenance (lot 4) ont un sens pour Abir ; la RH et la
banque, moins.

Sur l'**IA**, Dental Pilot a une avance d'un an et demi et en a fait son
identité. Nous ne rattraperons pas ça avant janvier et nous avons décidé de ne
pas essayer (D-03, D-10). Ce qui se fait sans IA — devis par recherche de
libellé, découpage de séances par règles, opportunités par requêtes — couvre
la moitié de ce que leur IA montre en démo.

### 5.2 Où faire mieux

1. **La cotation qui ne peut pas se tromper.** Dental Pilot recommande ; Nubia
   interdit, avec des règles vérifiées formellement (D-08). Sur un marché où
   la caisse requalifie en fraude, c'est l'argument que Dental Pilot ne peut
   pas tenir avec une IA à indice de confiance.
2. **Les données restent chez le centre.** Box LAN, zéro transit internet,
   pilotage technique seul (D-05 → D-07) — face à un cloud + crédits IA dont
   on ne sait pas où il tourne. Dental Pilot annonce une version locale ; nous
   pouvons l'avoir en octobre.
3. **Le patient est un utilisateur, pas un destinataire d'e-mails.** App
   native, proches, pharmacie, ordonnances, passeport implantaire : Dental
   Pilot n'a que la page devis.
4. **Le cabinet dans son écosystème** : pharmacie, infirmière, site de
   réservation, interop FHIR / HL7. Dental Pilot est un silo dentaire.
5. **Pas de compteur de crédits.** 300 €/mois tout compris (CR 08/09) contre
   abonnement + onboarding 390 € + crédits IA à la fonction.
6. **Le module rejets et prise en charge d'Abir** — Dental Pilot n'a que des
   « retours FSE » annoncés et une estimation « en cours de travail ».

### 5.3 Ce que ce benchmark change à la roadmap du 16/09

- **Socle 1** : la « reprise de données » n'est pas une validation, c'est un
  **développement** — connecteur DSIO en priorité, CSV Doctolib ensuite. À
  chiffrer en semaines, à démarrer dès la semaine 1. Sans lui, la box du
  centre pilote démarre vide.
- **Socle 3** : ajouter explicitement la vue « opportunités », les tâches
  assignables, les briefs et le moteur de courriers — tous à faible effort,
  tous visibles en démo.
- **Socle 4** : pièces jointes au devis, attestation d'information,
  bibliothèque de consentements.
- **Lot 4 (ARS)** remonte d'un cran : Dental Pilot vend déjà « conformité +
  veille réglementaire », et c'est le module « qui n'existe nulle part » selon
  Abir. Il existe chez eux.
- **Design (socle 5)** : la comparaison écran à écran est sans appel. Le
  schéma dentaire réaliste et les dashboards à widgets sont le standard
  attendu.

## 6. Annexe — carte de la démo

| Segment | Minute | Écran |
|---|---|---|
| 01-02 | 0:00 | Login, promesse « pilote automatique », multi-device |
| 03-07 | 0:40 | Onboarding 5 étapes, invitations, migration Logos / DSIO / Doctolib, signature-tampon, onboarding 390 € |
| 08 | 3:43 | Dashboard : KPI, prothèses du jour, opportunités, tâches |
| 09-12 | 4:50 | Fiche patient, schéma dentaire, favoris, groupements, catégories d'actes |
| 13 | 7:43 | Analyse de panoramique IA |
| 14-15 | 8:13 | Plan de traitement, séances, planification agenda |
| 16-17 | 8:51 | Devis IA par mots-clés, devis depuis les actes |
| 18-21 | 10:53 | Devis : envoi, pièces jointes, signature, espace patient, suivi devis |
| 22-24 | 14:01 | Planification des séances, actes réalisés, labo |
| 25-27 | 16:07 | Dictée, courriers, correspondants |
| 28-30 | 17:45 | CR opératoire, facture / FSE, paro, traçabilité implants, ortho, endo |
| 31 | 21:17 | Compta labo, marge |
| 32-35 | 21:57 | Agenda, liste d'attente, widget RDV, rappels, secrétariat |
| 36-38 | 24:54 | Inbox IA, prothèses 3Shape / MEDIT |
| 39-41 | 26:30 | Stock, fournisseurs, correspondants, e-réputation |
| 42-45 | 27:55 | Templates, questionnaire, palette d'outils |
| 46-50 | 30:10 | Stérilisation, borne, conformité, maintenance, DMSM, pointeuse |
| 51-55 | 32:30 | Planning équipe, BI, frais labo, recouvrement, banque |
| 56-58 | 35:00 | Équipe, droits, carte de visite, support IA |
| 59-62 | 36:51 | Paramètres, préférences IA, comportements auto, crédits IA |
