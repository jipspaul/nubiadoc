# 02 — Découpe projet step-by-step

> Comment on attaque le projet « comme une équipe de 10 dev senior ». Ce document donne **deux lectures superposées** :
> - **La découpe idéale** (organisation, workstreams, épics) — telle qu'une équipe de 10 la mènerait, ce que tu as demandé.
> - **Le chemin réaliste solo / pré-seed** — la même découpe re-séquencée pour une personne sans financement, en s'appuyant sur les conclusions de `01-critique-du-brief.md`.
>
> Front confirmé : **Flutter** (app patient). Back : **NestJS modular monolith**. Hébergement souverain managé Scaleway.

---

## A. Comment lire ce plan

Un projet santé se découpe en **workstreams** (lignes de travail parallèles, chacune « ownée » par un profil), eux-mêmes découpés en **épics** (gros blocs de valeur), puis en **user stories** (incréments livrables et testables).

Notation utilisée :
- 🟥 **Bloquant / fondation** — rien ne tourne sans ça.
- 🟧 **MVP prod** — construit pour de vrai, données réelles, qualité production.
- 🎭 **MVP démo** — **présent et crédible à l'écran pour la démo investisseurs, mais mocké** (données simulées, pas branché en prod). Doit avoir l'air réel, sans la charge production/conformité.
- 🟦 **Post-MVP** — reporté explicitement (voir critique §4).
- `[Solo: …]` — adaptation pour une personne seule.

> **Décision produit (override fondateur)** : la démo investisseurs impose que **l'app patient montre l'intégralité des rubriques 1 à 12 du PDF**. Celles qui ne peuvent pas être livrées en qualité production dans le temps imparti sont **mockées (🎭)** plutôt que reportées. **Seule la section 13 « Fonctionnalités avancées » est exclue** (téléconsultation vidéo, chat IA, traduction auto, questionnaire pré-consult intelligent, enquête satisfaction) — à l'exception de « paiement en ligne », conservé via le wedge devis/acompte (WS5).
>
> ⚠️ **Garde-fou** : un écran 🎭 mocké pour la démo ne doit **jamais** manipuler de **vraie donnée patient** tant que la conformité HDS/RGPD de l'Étape 4 n'est pas en place. Démo = données fictives. C'est ce qui rend l'« app complète » montrable sans ouvrir prématurément le périmètre de conformité.

---

## B. L'organisation cible (équipe de 10 senior)

Si tu avais 10 seniors demain, voici comment je découperais les responsabilités. Cette grille sert aussi de **carte des compétences à recruter / sous-traiter** dans l'ordre.

| # | Workstream | Owner (profil) | Responsabilité |
|---|---|---|---|
| WS1 | **Plateforme & Sécurité/HDS** | DevOps/SRE + appui sécurité | Infra Scaleway, CI/CD, secrets, RLS, chiffrement, audit log, conformité technique. |
| WS2 | **Core backend & modèle de données** | Backend senior #1 | NestJS, modèle multi-tenant, API, auth, domaine métier. |
| WS3 | **App patient (Flutter)** | Mobile senior | App iOS/Android : RDV, dossier, notifications, signature, paiement. |
| WS4 | **Back-office praticien/secrétariat (Flutter Web/Desktop)** | Frontend senior | Agenda, fiche patient, gestion devis, messagerie côté cabinet. Même stack que WS3 → un seul écosystème Dart. |
| WS5 | **Paiements & Signature** | Backend senior #2 | Devis, Stripe, GoCardless, Yousign, Alma, échéanciers, relances. |
| WS6 | **IA** (post-MVP) | ML/IA | Scribe vocal, triage messagerie. Démarre seulement en Phase IA. |
| WS7 | **Produit & Design** | PM healthtech + UX/UI | Specs, design system, parcours, recherche utilisateur cabinets. |
| WS8 | **Compliance & Légal** | DPO externalisé + avocat santé | AIPD, DPA, registres RGPD, CGU, conformité. *Transverse, non codant.* |

> `[Solo: tu portes WS1→WS5 + WS7. Tu externalises WS8 (DPO + avocat santé, incompressible). WS6 (IA) n'existe pas avant la traction.]`

**Ordre de renfort recommandé quand l'argent arrive** : (1) un **backend/sécurité senior** pour WS1+WS5, (2) un **mobile Flutter**, (3) un **PM/CS healthtech** (ex-Doctolib/Nabla idéalement), (4) l'IA en dernier.

---

## C. La découpe en épics

### WS1 — Plateforme & Sécurité/HDS

| Épic | Stories clés | Prio |
|---|---|---|
| E1.1 Socle infra | Compte Scaleway HDS, conteneurs managés, Postgres managé, Object Storage, environnements dev/staging/prod | 🟥 |
| E1.2 CI/CD | Repo, GitHub Actions (lint/test/build/deploy), Terraform infra-as-code, secret manager managé | 🟥 |
| E1.3 Sécurité de base | RLS multi-tenant, chiffrement colonne (données médicales), scrubbing PII des logs, MFA | 🟥 |
| E1.4 Audit & rétention | Audit log append-only (table Postgres partitionnée), soft-delete + politiques de rétention 20/30 ans | 🟥 |
| E1.5 Observabilité & analytics | **PostHog (EU Cloud)** : analytics produit + session replay + error tracking ; logs/metrics managés, alerting basique | 🟧 |

### WS2 — Core backend & modèle de données

| Épic | Stories clés | Prio |
|---|---|---|
| E2.1 Modèle multi-tenant | Entités Cabinet, User, CabinetMembership (N-N, rôles/permissions), RLS par cabinet | 🟥 |
| E2.2 Auth & rôles | Inscription/connexion email+MFA, gestion des rôles praticien/secrétariat/patient, cloisonnement R.4127-72 | 🟥 |
| E2.3 Domaine patient | Patient (INS chiffré, état civil, mutuelle), MedicalRecord, ConsentRecord | 🟥 |
| E2.4 Domaine RDV | Appointment (status, motif), agenda praticien, créneaux, règles de réservation | 🟧 |
| E2.5 Domaine documents | Stockage documents (Object Storage), coffre-fort, catégories (devis, ordo, radio, CR…) | 🟧 |

### WS3 — App patient (Flutter)

Périmètre = **l'intégralité des rubriques 1-12 du `nubiaDoc.pdf`**, présentes dans l'app pour la démo. La colonne « Prio » indique ce qui est construit en **prod (🟧)** vs **mocké pour la démo (🎭)**. La rubrique 13 est exclue.

| Épic | Rubrique PDF | Stories clés | Prio |
|---|---|---|---|
| E3.1 Onboarding & compte | 3 | Inscription, connexion, profil, infos admin (mail/adresse/tél/sécu/mutuelle), questionnaire médical | 🟧 |
| E3.2 Rendez-vous | 1 | Prise/modif/annulation, RDV à venir, historique, confirmations/rappels auto, demande de rappel, liste d'attente | 🟧 *(liste d'attente 🎭)* |
| E3.3 Tableau de bord patient | 10 | Prochain RDV, docs à signer, questionnaires, messages non lus, paiements en attente, suivis recommandés, actions | 🟧 |
| E3.4 Messagerie patient | 2 | Échanges cabinet, classification urgent/non urgent, envoi photos/documents, réponses, notifs | 🟧 |
| E3.5 Dossier & coffre-fort | 3, 11 | Consultation docs admin/médicaux (ordo, CR, radios, CBCT, photos), téléchargement, conservation sécurisée | 🟧 |
| E3.6 Signature électronique | 4 | Signature consentements + devis, validation docs admin, historique des signatures | 🟧 |
| E3.7 Notifications | 5 | Push (zéro PII) : RDV, document, signature, questionnaire, message, paiement, document manquant | 🟧 |
| E3.8 Espace financier patient | 6 | Consultation devis/factures, historique règlements, montant restant, échéances, rappels paiement | 🟧 *(échéancier/financement 🎭)* |
| E3.9 Plan de traitement | 7 | Soins réalisés/restants, prochaines étapes, RDV associés, coût global, reste à charge estimé | 🎭 |
| E3.10 Passeport implantaire | 8 | Marque/réf/lot/date/position implants, documents associés, téléchargement PDF | 🎭 |
| E3.11 Suivi & prévention | 9 | Rappels contrôle/détartrage/implanto/paro/ortho/post-chirurgie, relance > 1 an | 🟧 *(moteur de rappels simple ; scénarios cliniques 🎭)* |
| E3.12 Infos pratiques cabinet | 12 | Coordonnées, horaires, plan d'accès, contacts d'urgence, infos pratiques | 🟧 |
| ~~E3.x Fonctionnalités avancées~~ | 13 | Téléconsult vidéo, chat IA, traduction auto, questionnaire pré-consult intelligent, enquête satisfaction | ❌ *exclu (sauf paiement en ligne → wedge WS5)* |

> **Lecture** : tout ce qui est 🟧/🎭 apparaît dans l'app montrée aux investisseurs. Le 🎭 (plan de traitement, passeport implantaire, scénarios de suivi, échéanciers) est affiché avec des **données fictives réalistes** : l'écran existe, il est beau, il raconte l'histoire produit, mais la logique métier/conformité lourde derrière est reportée post-levée. Cf. critique §4 — ces modules restaient pertinents *en tant que vision*, on les avance ici uniquement pour la valeur démo.

### WS4 — Back-office praticien/secrétariat (Flutter Web/Desktop)

| Épic | Stories clés | Prio |
|---|---|---|
| E4.1 Agenda cabinet | Vue agenda, gestion créneaux, validation/déplacement RDV | 🟧 |
| E4.2 Fiche patient | Vue dossier, documents, historique, ajout de pièces | 🟧 |
| E4.3 Gestion devis | Création devis + lignes (CCAM), versioning, envoi au patient | 🟧 |
| E4.4 Messagerie cabinet | File des messages, classification urgent/non urgent (règles simples au début), réponse | 🟧 |
| E4.5 Liste d'attente | Inscription désistement, proposition de créneau libéré | 🟦 |

### WS5 — Paiements & Signature (le wedge monétisable)

| Épic | Stories clés | Prio |
|---|---|---|
| E5.1 Devis | Génération, versioning immuable (SHA-256 + horodatage), envoi patient | 🟧 |
| E5.2 Signature électronique | Intégration Yousign (eIDAS avancé), signature consentements + devis, historique | 🟧 |
| E5.3 Acompte & paiement | Stripe (CB), GoCardless (SEPA), encaissement acompte, statut de paiement | 🟧 |
| E5.4 Financement fractionné | Alma 3x/4x/10x, parcours de souscription, rev-share | 🟦 |
| E5.5 Échéancier & relances | PaymentSchedule multi-jalons, relances J+3/J+7/J+15 (BullMQ, pas Temporal) | 🟦 |

### WS6 — IA (🟦 entièrement post-MVP, post-traction)

Scribe vocal (Whisper managé + Mistral API), triage messagerie ML, analytics no-show. **Démarre seulement après le pilote et après cadrage AI Act/MDR.** Voir critique §3.5 et §6.

### WS7 — Produit & Design (transverse)

Design system, parcours patient/praticien, **entretiens de 5-10 cabinets dentaires** (validation pricing & douleurs), specs d'acceptation. À mener *avant* de coder chaque épic.

### WS8 — Compliance & Légal (transverse, non codant)

AIPD (avant tout dev touchant la donnée de santé), DPA avec sous-traitants, registres RGPD, CGU/consentements, choix hébergeur HDS, cadrage MDR pour exclure le dispositif médical du périmètre.

---

## D. La roadmap réaliste solo / pré-seed

On abandonne le calendrier « 18 mois / 7 piliers ». Les étapes sont **séquentielles** (un seul exécutant), pas parallèles. Les durées sont des ordres de grandeur pour 1 personne expérimentée à temps plein ; ajuste selon ta disponibilité réelle.

> **Deux cibles à ne pas confondre** :
> - 🎬 **Démo investisseurs** = l'app patient **complète à l'écran** (rubriques 1-12, mocks autorisés 🎭), sur **données fictives**. C'est ce qui se montre pour lever.
> - 🚀 **Pilote prod payant** = un périmètre **plus étroit mais réel** (les 🟧 production), avec conformité HDS/RGPD, chez un vrai cabinet.
>
> On atteint d'abord la démo (moins de conformité, beaucoup d'UI), puis on durcit en prod le sous-ensemble qui crée la valeur. La démo réutilise le même socle technique : les écrans 🎭 sont des vues Flutter finies branchées sur un jeu de données fictif, pas du jetable.

### Étape 0 — Cadrage & fondations *(≈ 3-5 semaines)*
**But : pouvoir coder en sécurité et savoir quoi coder.**
- WS7 : entretiens 5-10 cabinets dentaires → valider le wedge et le pricing.
- WS8 : engager DPO externalisé + avocat santé, lancer l'AIPD, choisir l'hébergeur HDS.
- WS1 : repo, CI/CD, environnements, Postgres managé, Object Storage, PostHog (EU Cloud).
- WS2 : squelette NestJS modular monolith + modèle multi-tenant + RLS + auth email/MFA.
- WS7 : design system minimal + maquettes des parcours MVP.
- **Go/No-Go G0** : AIPD lancée, hébergeur HDS choisi, socle technique déployé en staging, wedge confirmé par ≥5 cabinets. ✅ → Étape 1.

### Étape 1 — Cœur RDV + dossier patient *(≈ 6-10 semaines)*
**But : un patient prend RDV et accède à son dossier ; un cabinet gère son agenda.**
- WS2 : domaines Patient, RDV, Documents.
- WS3 : app Flutter — onboarding (E3.1), RDV (E3.2), tableau de bord (E3.3), dossier/coffre-fort (E3.5), notifications (E3.7), infos cabinet (E3.12). *(Messagerie E3.4 durcie à l'Étape 3.)*
- WS4 : back-office Flutter minimal — agenda (E4.1), fiche patient (E4.2).
- **Livrable L1** : prise de RDV en ligne + dossier patient consultable, démontrable sur **données fictives**.
- **Go/No-Go G1** : parcours RDV bout-en-bout testé, sécurité de base auditée en interne. ✅ → Étape 2.

### Étape 2 — Devis, signature, acompte (le wedge) *(≈ 6-10 semaines)*
**But : le cabinet émet un devis, le patient le signe et paie un acompte. C'est ce qui se vend.**
- WS5 : devis + versioning (E5.1), Yousign (E5.2), Stripe/GoCardless acompte (E5.3).
- WS4 : interface création/suivi devis (E4.3).
- WS3 : côté patient — consultation/signature devis + paiement acompte.
- **Livrable L2** : premier devis dentaire signé en ligne avec acompte encaissé (env. test).
- **Go/No-Go G2** : flux paiement/signature conforme et testé, CGU validées par l'avocat. ✅ → Étape 3.

### 🎬 Jalon DÉMO INVESTISSEURS — app patient complète *(≈ 3-5 semaines, mocks)*
**But : montrer l'app entière (rubriques 1-12 du PDF) à un investisseur, sur données fictives.**

On empile sur le vrai socle des Étapes 1-2 les écrans manquants du PDF, en qualité **démo (🎭)** :
- WS3 : espace financier patient (E3.8), plan de traitement (E3.9), passeport implantaire (E3.10), suivi & prévention (E3.11), messagerie côté patient (E3.4 en UI), signature (E3.6) si pas déjà finie.
- WS7 : jeu de **données fictives réalistes** (patients, RDV, devis, implants, radios factices), scénario de démo scripté, polish UI.
- **Garde-fou** : aucune vraie donnée patient. Tout est fictif, isolé d'un éventuel environnement prod.
- **Livrable D** : build démo de l'app patient couvrant les 12 rubriques, jouable de bout en bout devant un VC.
- **Go/No-Go GD** : parcours de démo fluide, rien ne casse à l'écran, histoire produit lisible. ✅ → poursuite vers le pilote prod (Étape 3) **ou** tour de table.

> Ce jalon peut être **avancé** si tu dois pitcher tôt : avec plus de mocks (et un wedge encore en cours), tu peux montrer l'app avant la fin de l'Étape 2. Le compromis = moins de « vrai » sous le capot.

### Étape 3 — Messagerie sécurisée *(≈ 4-6 semaines)*
**But : échange patient ↔ cabinet, cloisonné et chiffré.**
- WS4/WS3 : Conversation + Message chiffrés, classification urgent/non urgent par **règles simples** (mots-clés, pas d'IA), conversion message → RDV.
- **Livrable L3** : messagerie fonctionnelle, cloisonnement secrétariat/praticien.

### Étape 4 — Pilote réel *(≈ 4-8 semaines de préparation + run)*
**But : passer en production chez 1 cabinet avec de vraies données.**
- WS8 : AIPD validée, DPA signés, hébergement HDS confirmé en prod, registres RGPD en place.
- WS1 : durcissement sécurité, sauvegardes/PRA, monitoring, runbook d'incident.
- WS7 : onboarding du cabinet, support défini.
- **Go/No-Go G3 (le plus important)** : conformité HDS/RGPD réelle prête → **bascule sur données patient réelles**. ✅ → pilote en prod.

### Étape 5 et au-delà — Itération sur traction *(post-pilote)*
On **passe en prod les écrans qui étaient mockés (🎭) pour la démo** et on rouvre le backlog 🟦, dans l'ordre de valeur prouvée : financement Alma + échéanciers/relances (E5.4/E5.5), plan de traitement & passeport implantaire en version réelle (E3.9/E3.10), scénarios de suivi/prévention (E3.11), liste d'attente (E4.5). **L'IA (WS6), le check-in géofencé, l'analytics ML, Ségur/PSC et Mon Espace Santé ne s'ouvrent qu'après plusieurs cabinets payants et un cadrage réglementaire dédié (AI Act, MDR).**

---

## E. Backlog priorisé (MoSCoW) du MVP

Le « MVP » couvre désormais **les 12 rubriques du PDF** (override démo). Les Must-have « 🎭 » sont obligatoires **à l'écran pour la démo** mais peuvent être mockés ; leur version prod arrive post-levée.

| Must have (prod) | Must have (🎭 démo, mockable) | Should / Could have | Won't have (cette version) |
|---|---|---|---|
| Multi-tenant + RLS + chiffrement | Plan de traitement patient | Liste d'attente désistement | IA Scribe vocal |
| Auth + rôles + cloisonnement | Passeport implantaire | Financement Alma | Check-in géofencé / borne |
| RDV en ligne + agenda cabinet | Suivi & prévention (scénarios) | Échéancier + relances auto | Analytics ML no-show |
| Dossier patient + coffre-fort | Espace financier (échéanciers) | Classification messages avancée | Parcours de soins réseau |
| Devis + versioning + signature | | | Mon Espace Santé / Ségur |
| Acompte / paiement (Stripe/SEPA) | | | Vérif interactions médic. (= DM) |
| Messagerie sécurisée (règles) | | | Téléconsultation vidéo |
| Notifications push | | | Chat IA / traduction auto |
| Espace financier (consultation) | | | Questionnaire pré-consult intelligent |
| Infos pratiques cabinet | | | Enquête de satisfaction |
| AIPD + conformité HDS pilote | | | Pro Santé Connect / Marketplace API |

---

## F. Conventions de delivery (à fixer dès l'Étape 0)

**Definition of Ready (une story est prête à être prise)**
- Valeur utilisateur claire + critères d'acceptation écrits.
- Impacts RGPD/sécurité identifiés (donnée de santé ? consentement ? rétention ?).
- Maquette ou contrat d'API défini.
- Pas de dépendance bloquante non résolue.

**Definition of Done (une story est finie)**
- Code revu (même en solo : PR + relecture différée), tests automatisés verts.
- Pas de PII en clair dans les logs.
- RLS/permissions vérifiées sur la story.
- Déployée en staging et testée sur le parcours bout-en-bout.
- Doc à jour si la story change l'architecture ou un contrat d'API.

**Cadence solo suggérée** : itérations de 2 semaines, une démo à toi-même (ou à un cabinet design partner) en fin d'itération, un point conformité à chaque Go/No-Go.

---

## G. Jalons & critères Go/No-Go (récap)

| Jalon | Condition de passage |
|---|---|
| **G0** Fondations | Wedge validé (≥5 cabinets), AIPD lancée, hébergeur HDS choisi, socle en staging |
| **G1** Cœur RDV | Parcours RDV + dossier bout-en-bout sur données fictives, sécurité de base OK |
| **G2** Wedge monétisable | Devis signé + acompte encaissé en test, CGU validées avocat |
| **GD** 🎬 Démo investisseurs | App patient complète (rubriques 1-12) jouable sur données fictives, parcours fluide |
| **G3** Pilote prod 🚨 | Conformité HDS/RGPD **réelle** prête → autorisation données patient réelles |
| **G4** Traction | ≥3 cabinets payants → réouverture backlog 🟦 + premiers recrutements |

---

## H. Ce que cette découpe change par rapport au brief

- On passe de **« 7 piliers en 18 mois à 7 devs »** à **« app patient complète pour la démo (mocks autorisés) + 1 wedge réel jusqu'au pilote payant, exécutable seul »**.
- On sépare nettement **démo investisseurs (🎬 tout à l'écran, fictif)** et **pilote prod (🚀 plus étroit, réel, conforme)** — deux jalons, deux niveaux d'exigence.
- On **reporte explicitement** tout ce qui est prématuré (IA, géofencing, analytics, réseau, Ségur) au lieu de le porter en dette dès le départ.
- On garde les **bons fondamentaux** du brief (RLS, chiffrement, audit, soft-delete) parce qu'ils sont durs à rétrofitter.
- On **élimine les briques d'ops** qu'un solo ne peut pas tenir (K8s, Temporal, NATS, observabilité/Keycloak/Sentry self-hosted) au profit du managé Scaleway.
- On rend le projet **finançable** : un wedge en prod chez un cabinet payant est une *preuve* qui ouvre le seed, bien plus qu'un slide de 7 piliers.
