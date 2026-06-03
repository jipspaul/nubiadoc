# Projet — Plateforme SaaS HealthTech "Tout-en-un" (concurrent Doctolib)

## Contexte du projet

Développement d'un SaaS médical français concurrent à Doctolib, positionné comme une **plateforme tout-en-un** intégrant prise de rendez-vous, logiciel métier praticien et hub secrétariat. La solution est conçue pour résoudre les frustrations actuelles via une automatisation poussée et l'intégration native d'IA, dans le respect strict du cadre légal français (HDS, RGPD, secret médical, Ségur, AI Act).

---

## Positionnement et cible

### Cible primaire MVP
**Dentistes et médecine esthétique** (extension prévue aux vétérinaires en Phase 2, puis kinés/paramédicaux, puis généralistes).

**Pourquoi ce segment** : capacité de paiement élevée (CA cabinet 250–700k€/an), pertinence à 100% des 4 piliers (devis omniprésents, no-shows critiques, salle d'attente complexe), logiciels concurrents vieillissants (Julie, Logos, Veasy, Doxadent), communauté soudée favorisant le bouche-à-oreille.

### Pricing
Modèle tout-compris, plus simple et lisible que les offres à tiroirs de Doctolib :

| Plan | Prix | Cible |
|---|---|---|
| Solo | 79€/mois/praticien | Cabinet individuel, jusqu'à 2 praticiens |
| Cabinet | 99€/mois/praticien | 3+ praticiens, multi-secrétariat, multi-site |
| Centre | Sur devis | MSP, centres de santé, >10 praticiens |

**Revenus transactionnels complémentaires** : commission 0,5% sur acomptes encaissés, rev-share 25-30% sur financement Alma/Younited, commission lecture mutuelle, marketplace API tierce (Phase 2+).

**ARPU réel cible** : 110-150€/mois/praticien tout compris.

### Positionnement marketing
- "Tarif unique tout-compris" face aux options empilées de Doctolib
- "100% souverain français" — données jamais soumises au droit américain
- "IA française" — Mistral + Scaleway, pas OpenAI/Anthropic
- "Conformité Ségur native" dès la V1

---

## Les 4 piliers fondateurs du MVP

### Pilier 1 — Check-in multimodal automatisé
- QR code via app mobile, QR code web sans app, ou borne tablette
- Pré-check-in J-1 (notif veille à 18h, questionnaire, OCR mutuelle, acompte)
- Géofencing intelligent opt-in (détection arrivée dans rayon 200m)
- File d'attente virtuelle "promenade" (notif 5-10 min avant son tour)
- Fallback SMS magique pour patients sans smartphone récent
- Mode accompagnant et PMR (signalement automatique au praticien)
- Détection des retards critiques avec relance puis ré-allocation auto

### Pilier 2 — Gestion complète des devis
- Signature électronique eIDAS niveau avancé via Yousign
- Paiement d'acompte en ligne (Stripe + GoCardless SEPA)
- Plan de financement natif (Alma / Younited / Cofidis 3x-12x)
- Échéancier multi-jalons (ortho, implantologie sur 18 mois)
- Comparateur de prise en charge mutuelle en temps réel (Almerys/Viamedis)
- Génération du devis depuis l'IA Scribe (pré-rempli avec cotations CCAM)
- Relances intelligentes J+3 / J+7 / J+15 (templates A/B testés)
- Gestion automatique du délai de rétractation légal esthétique (14 jours)

### Pilier 3 — Messagerie asynchrone intelligente
- Triage IA 3 niveaux :
  - Niveau 1 (50-60%) — auto-résolu par IA via templates pré-validés
  - Niveau 2 (30-35%) — secrétariat
  - Niveau 3 (5-10%) — praticien
- Détection d'urgence par NLP + sentiment analysis (mots-clés cliniques, escalade + bandeau 15/SAMU)
- Conversation triadique cloisonnée patient ↔ secrétariat ↔ praticien
- Conversion message → RDV en 1 clic
- Mode vacances/remplacement avec routage automatique
- Intégration MSSanté pour échanges entre professionnels

### Pilier 4 — IA Scribe médical vocal
- Whisper Large v3 self-hosted sur Scaleway GPU H100 (français)
- Génération clinique via Mistral Large (souverain, français)
- Privacy by design : audio local first, chiffrement E2E, suppression sous 7 jours
- Templates configurables par spécialité (SOAP pour généralistes, lésions pour dermato, quadrants pour dentistes)
- Validation humaine obligatoire item-par-item (jamais intégration auto au DPI)
- Score de confiance par section affiché au praticien
- Pré-cotation CCAM/NGAP automatique
- Détection prescriptions verbales + vérif interactions médicamenteuses (BCB Dexther)
- Consentement patient explicite et révocable
- Export FHIR R4 natif (interopérabilité DMP/Mon Espace Santé)

---

## Piliers additionnels stratégiques

### Pilier 5 — Cabinet Intelligence (analytics et optimisation)
- Prédiction no-shows par ML (sur-réservation intelligente sur créneaux à risque)
- Optimisation du planning (regroupement actes, alternance courts/longs)
- Benchmark anonymisé inter-cabinets
- Détection sous-cotation CCAM (5-15% du CA souvent perdu)

### Pilier 6 — Parcours de soins coordonné
- Adressage en 1 clic à un confrère du réseau avec dossier pré-partagé
- Téléexpertise asynchrone entre confrères (cotée RQT/RCQ)
- Vue 360° du parcours patient pour le médecin traitant
- Effet réseau créant un moat défensif

### Pilier 7 — Espace patient Mon Espace Santé compatible
- Référencement Ségur Vague 2/3 (financement État)
- Carnet de santé enrichi côté patient
- Intégration objets connectés (Apple Health, Withings, Dexcom)
- Rappels de prévention personnalisés

### Améliorations transversales
- Multi-sites et cabinet groupé natifs dès le MVP
- Mode hors-ligne praticien (DPI consultable sans connexion)
- API ouverte + marketplace tierce (Phase 2+)
- Module conformité automatique (registres RGPD, journal d'accès, AIPD pré-remplie)

---

## Stack technique

> ⚠️ Section = **brief d'origine (maximaliste)**. La stack réellement retenue est dégraissée dans `docs/01-critique-du-brief.md` et figée dans `docs/04-architecture.md`. **Stack actée** : back **Rust / Axum**, front **Flutter partout** (un seul écosystème Dart), temps réel **WebSockets**.

### Frontend
- **Mobile patient** : Flutter 3.x + Bloc (flutter_bloc) + Dio (codebase unique iOS/Android)
- **Web patient (fallback QR sans app)** : Flutter Web embarqué + PWA
- **Interface Praticien** : Flutter Web/Desktop — un seul écosystème Dart
- **Interface Secrétariat** : Même stack Flutter que praticien (mutualisation maximale)

### Backend
- **API principale** : **Rust / Axum**, architecture modular monolith (workspace de crates) ; accès données SQLx + RLS Postgres
- **Microservices IA** : Python (FastAPI) pour ML/Whisper/Mistral — post-MVP uniquement
- **Orchestration workflows** : jobs async **apalis** (Redis) au MVP ; Temporal.io reconsidéré post-traction si workflows longs
- **Temps réel** : **WebSockets** natifs Axum/Tokio (fan-out pub/sub Redis), + FCM pour le push patient

### Data
- **Base principale** : PostgreSQL 16 (Scaleway Managed DB HDS) + pgvector + TimescaleDB + pg_trgm
- **Cache + sessions** : Redis 7 (Scaleway Managed)
- **Recherche** : Meilisearch (français, souverain)
- **Stockage documents** : Scaleway Object Storage HDS
- **Queue async** : NATS JetStream

### Authentification et identité
- **Auth backbone** : Keycloak self-hosted
- **Praticiens** : Pro Santé Connect (carte CPS / e-CPS) — obligatoire Ségur
- **Patients** : France Connect + inscription email classique

### Paiements et signatures
- **Cartes** : Stripe (France SAS, EU)
- **SEPA** : GoCardless
- **Financement fractionné** : Alma (3x/4x/10x)
- **Signature électronique** : Yousign (eIDAS niveau avancé) — backup Universign

### IA
- **Transcription** : Whisper Large v3 self-hosted sur Scaleway GPU H100
- **Génération clinique** : Mistral Large via Scaleway managed inference
- **Triage messagerie** : Mistral Small + classifier fine-tuné
- **Interactions médicamenteuses** : BCB Dexther (alternative Vidal)
- **OCR documents** : Mistral OCR / Tesseract

### Communications
- **Push mobile** : Firebase Cloud Messaging (zéro PII dans le push)
- **SMS** : OctoPush (souverain français) + Twilio en backup
- **Email transactionnel** : Brevo (ex-Sendinblue, français)

### Infrastructure et observabilité
- **Hébergement** : Scaleway Kapsule HDS (Kubernetes managé HDS)
- **CDN/WAF** : Scaleway Edge Services ou Bunny.net (européen)
- **Observabilité** : Grafana + Prometheus + Loki + Tempo (self-hosted)
- **Erreurs front** : Sentry self-hosted
- **CI/CD** : GitHub Actions + ArgoCD + Terraform
- **Secrets** : HashiCorp Vault ou Scaleway Key Manager

---

## Architecture de base de données — points structurants

### Entités principales
- **Cabinet** (multi-tenant) — raison sociale, SIRET, FINESS, spécialité
- **User** (rôle générique) — email, RPPS/ADELI, MFA
- **Patient** — INS, état civil, mutuelle, consentements
- **Practitioner** — RPPS, spécialité, conventions
- **CabinetMembership** — relation N-N User/Cabinet avec rôle et permissions
- **Appointment** — RDV avec status, motif, pré-checkin
- **CheckInEvent** — événement check-in multi-mode
- **MedicalRecord** — dossier patient (antécédents, allergies, traitements)
- **ClinicalNote** — note clinique chiffrée, actes CCAM, validation IA
- **ScribeSession** — session IA (audio, transcript, score confiance)
- **DentalChart** — spécifique dentaire (status par dent, traitements planifiés)
- **Quote** + **QuoteItem** — devis versionnés avec lignes CCAM
- **Signature** — signature Yousign avec certificat probant
- **PaymentSchedule** + **Payment** — échéancier multi-jalons
- **Conversation** + **Message** — messagerie chiffrée triée par IA
- **WaitingListEntry** — liste d'attente intelligente avec scoring
- **AuditLog** — journal append-only (TimescaleDB, rétention 10 ans)
- **ConsentRecord** — traçabilité des consentements RGPD

### Décisions structurantes
- **Multi-tenant par Row-Level Security PostgreSQL** — cloisonnement au niveau base, même un bug applicatif ne peut pas faire fuiter entre cabinets
- **Chiffrement au niveau colonne** pour les données médicales (clé par cabinet via KMS)
- **INS traité comme PII critique** — chiffré, jamais en clair dans les logs
- **Audit log append-only** — TimescaleDB avec partitioning automatique
- **Soft-delete obligatoire** sur tout ce qui touche au médical (rétention 20 ans, 30 ans pour mineurs)
- **Versioning natif des devis** — devis signé = immutable + SHA-256 + horodatage qualifié
- **JSONB flexible** pour les champs métier évolutifs (mutuelle, antécédents, structured_summary, teeth_status)

---

## Défis techniques majeurs et stratégies de mitigation

### Défi 1 — Conformité HDS et secret médical au niveau technique
**Risque** : confondre hébergement HDS et conformité HDS. Retoquage à l'audit M+15 = retrait Ségur + risque CNIL.

**Mitigation** :
- Sprint 0 dédié sécurité (3 semaines) avant tout code métier
- CISO/security architect senior dès M+1 (consultant 2j/sem si pas full-time)
- Pré-audit HDS interne à M+10 (15-25k€)
- Audit HDS officiel par OCA accrédité à M+15 (25-40k€)
- Pen-test annuel obligatoire (Synacktiv, Quarkslab — 20-30k€/an)
- Cloisonnement strict secrétariat / praticien (R.4127-72 CSP)
- Middleware de scrubbing automatique des logs (NER + regex)

### Défi 2 — IA Scribe : qualité, latence, coût, responsabilité médicolégale
**Risque** : résumé erroné validé par fatigue = faute médicale + responsabilité éditeur du DSM.

**Mitigation** :
- Validation explicite item-par-item, jamais "tout valider d'un coup"
- Score de confiance prominent par section (rouge si <80%)
- Phase 1 : transcription brute + résumé descriptif uniquement
- Phase 2 (M+12+) : fine-tuning sur dataset dentaire FR (5-10k paires validées)
- Architecture découplée async (Temporal + NATS)
- CGU et consentement patient explicites + révocables
- Conservation audio 7 jours max sauf opt-in séparé
- Conformité AI Act EU 2026 (système IA à risque élevé)

### Défi 3 — Migration depuis l'incumbent (Doctolib, Julie, Logos, Veasy)
**Risque** : sans migration fluide, deal commercial mort malgré une démo réussie.

**Mitigation** :
- Équipe "Migration & Onboarding" dédiée dès M+8 (2 ingés data + 1 ex-secrétaire dentaire)
- Connecteurs propriétaires par incumbent (Julie SQL, Logos SQLite, Doctolib CSV+RPA, etc.)
- Pipeline OCR + LLM extraction pour les PDF archivés
- Mode "shadow / lecture seule" pendant 90 jours de transition
- Service "White Glove Migration" gratuit pour les 100 premiers cabinets
- Levier juridique RGPD article 20 (droit à la portabilité) si blocage Doctolib

### Défis secondaires à surveiller
- Synchronisation temps réel agenda + check-in + salle d'attente (race conditions)
- Pro Santé Connect homologation (3-4 semaines dev + 2 mois homologation ANS)
- SLA 24/7 healthcare-grade (architecture HA multi-AZ + astreinte payée dès M+10)

---

## Roadmap MVP — 18 mois

### Phase 0 — Fondations (M0–M1)
HDS, équipe, compliance, AIPD, architecture, design system.
Livrable : sandbox sécurisée, contrats DPA signés, dev kickoff.

### Phase 1 — Core MVP (M2–M5)
Auth, agenda, RDV, DPI timeline, app patient Flutter v1.
Livrable M5 : RDV en ligne + check-in QR fonctionnel chez un cabinet pilote.

### Phase 2 — Devis et acompte (M6–M8)
Yousign, Stripe, Alma, CCAM, échéanciers, relances IA.
Livrable M8 : premier devis dentaire signé en ligne avec acompte 3x.

### Phase 3 — Messagerie et salle d'attente (M9–M11)
Tour de contrôle, triage IA, no-show auto, liste d'attente.
Livrable M11 : 5 cabinets pilotes en production avec données réelles.

### Phase 4 — IA Scribe et optimisation (M12–M14)
Whisper FR + Mistral, templates dentaires, pré-cotation CCAM.
Livrable M14 : Scribe en production sur 15 cabinets.

### Phase 5 — Scale et certification (M15–M18)
Audit HDS officiel, référencement Ségur, migration tooling, sales playbook, préparation Series A.
Objectif M18 : 80-120 cabinets payants, MRR 80-120k€, levée 6-10M€.

---

## Financement et équipe cible

### Stratégie de financement
- **Seed 2,5M€ sur 18 mois** (burn 130k€/mois, runway 19 mois)
- Objectif M+18 : 80 cabinets payants → ouverture Series A 6-10M€

### Équipe cible (12-15 personnes)
- **Tech (7)** : 1 CTO/Lead, 2 backend senior (1 dédié sécurité/HDS), 1 mobile senior, 1 frontend, 1 DevOps/SRE, 1 ML/IA
- **Produit/Design (2)** : 1 PM healthtech (ex-Doctolib/Nabla/Alan/Tilak idéalement), 1 UX/UI senior
- **Go-to-market (3-4)** : 1 Head of Sales (B2B santé), 2 AE/SDR (réseau dentaire), 1 Customer Success
- **Compliance/Légal/Ops (1-2)** : DPO externalisé + 1 Ops/Compliance Manager

### Coûts compliance incompressibles à anticiper
- Audit applicatif sécurité : 30-50k€ initial
- DPO externalisé : 800-1500€/mois
- Pen-test annuel : 15-30k€
- Assurance RC pro tech santé : 8-15k€/an
- Conformité Ségur : 80-150k€ d'effort produit + 6 mois de process
- Avocat spécialisé santé : 15-25k€ setup initial
- **Total compliance à débourser avant la première facture : ~150-200k€**

---

## Contraintes légales et réglementaires obligatoires

### Hébergement et données
- Certification HDS obligatoire (hébergement + applicative)
- Hébergement souverain français privilégié (éviter Cloud Act US)
- Chiffrement bout-en-bout messagerie et documents médicaux
- Rétention dossier patient : 20 ans après dernière consultation (30 ans mineurs)
- Audit log conservé 10 ans minimum

### Identifiants et interopérabilité
- INS (Identifiant National de Santé) obligatoire pour Ségur
- Pro Santé Connect obligatoire pour authentification praticien (Ségur)
- MSSanté pour échanges entre professionnels de santé
- FHIR R4 pour interopérabilité DMP / Mon Espace Santé
- Référencement Ségur Vague 2/3 (financement État pour les cabinets adoptants)

### IA et automatisation
- Conformité AI Act EU (Scribe IA = système à risque élevé)
- Consentement patient explicite et révocable pour l'IA
- Validation humaine obligatoire de tout contenu IA avant intégration DPI
- Documentation technique IA et gestion des risques

### Signature et paiement
- Signature électronique eIDAS niveau avancé minimum
- Archivage légal probant chez tiers archiveur
- Délai de rétractation 14 jours sur actes esthétiques

### RGPD
- DPO externalisé obligatoire dès le démarrage
- AIPD validée avant développement de toute fonction touchant aux données de santé
- Registre RGPD et journal d'accès au dossier patient
- Droit à la portabilité (article 20) honoré

---

## Architecture évolutive — extensions Phase 2+

Modules anticipés mais hors-MVP, à intégrer dans l'architecture initiale sans dette technique :
- Téléexpertise asynchrone entre confrères
- Lecture carte Vitale physique (lecteur PC/SC)
- Intégration objets connectés (Apple Health, Withings, Dexcom)
- Marketplace API tierce (radio 3D, scanners intra-oraux, capteurs)
- Téléconsultation vidéo
- Extension internationale (Belgique, Espagne, Italie)
- Offre établissements (cliniques, MSP, centres pluripro)

---

## Métriques cibles M+18

| Métrique | Cible |
|---|---|
| Cabinets payants | 80-120 |
| MRR | 80-120k€ |
| ARPU réel (avec transactionnel) | 110-150€/mois/praticien |
| NRR (Net Revenue Retention) | >100% |
| NPS | >50 |
| Churn mensuel | <2% |
| CAC | <1500€/cabinet |
| LTV | >60 000€/cabinet sur 5 ans |
| LTV/CAC | >40x |

---

## Premières actions critiques

1. **Recrutement CTO** — démarrer immédiatement (3-6 mois pour profil senior healthtech FR)
2. **Design partners** — sécuriser 5-10 cabinets dentaires prêts à être pilotes
3. **Avocat spécialisé santé** — engagement immédiat pour CGU/DPA/AIPD (Bismuth, Houdart, Bensoussan)
4. **DPO externalisé** — recrutement pour valider l'AIPD avant tout dev
5. **Démarches Pro Santé Connect** — initier auprès de l'ANS dès Phase 0
6. **Pré-séries Seed** — pitch deck et premières introductions VC healthtech (Eurazeo, Bpifrance, Cathay, Serena)
