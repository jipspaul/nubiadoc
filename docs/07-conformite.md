# 07 — Conformité (checklist opérationnelle)

> Checklist actionnable HDS / RGPD / AIPD / AI Act / MDR / eIDAS pour un MVP santé. Conçue pour un contexte **solo / pré-seed** : on distingue ce qui est **bloquant avant la première donnée patient réelle** de ce qui peut attendre.
> Statuts : ☐ à faire · ◐ en cours · ☑ fait. *Owner par défaut : toi, sauf DPO/avocat externalisés.*
> ⚠️ Ce document est un guide d'ingénierie, **pas un avis juridique**. L'AIPD et les CGU/DPA doivent être validées par le DPO et l'avocat santé.

## Principe de séquencement
- **Dév sur données fictives** → conformité « légère ». La machinerie lourde se déclenche au **Go/No-Go G3** (première donnée patient réelle, cf. `02`).
- Trois chantiers à ne **jamais confondre** : (1) **hébergement HDS** (dès la 1re donnée réelle), (2) **conformité applicative / certification**, (3) **référencement Ségur**. Détail : `01` §1.

---

## 1. Hébergement & infrastructure HDS

| # | Item | Quand | Statut |
|---|---|---|---|
| 1.1 | Choisir un hébergeur **certifié HDS** (Scaleway HDS) pour Postgres/Redis/Object Storage/compute | Avant G3 | ☐ |
| 1.2 | Vérifier que **tu restes client** d'un hébergeur certifié (tu n'as pas à te certifier hébergeur toi-même) | Étape 0 | ☐ |
| 1.3 | Signer le **contrat HDS / clauses HDS** avec l'hébergeur | Avant G3 | ☐ |
| 1.4 | Cartographier les flux de données de santé (où elles transitent, où elles reposent) | Avant G3 | ☐ |
| 1.5 | Confirmer la **localisation UE** de toutes les données (éviter Cloud Act US) | Étape 0 | ☐ |
| 1.6 | Sauvegardes chiffrées + **test de restauration** documenté (PRA) | Avant G3 | ☐ |
| 1.7 | Plan de continuité (PCA) minimal + runbook d'incident | Avant G3 | ☐ |

> Ne pas confondre « hébergé chez un certifié HDS » (accessible dès J0) et « audit de conformité applicative » (plus tard). Cf. `01` §1.

---

## 2. RGPD

| # | Item | Quand | Statut |
|---|---|---|---|
| 2.1 | **DPO externalisé** engagé | Étape 0 | ☐ |
| 2.2 | **Registre des traitements** (art. 30) rédigé et tenu | Avant G3 | ☐ |
| 2.3 | **Bases légales** documentées par traitement (soins, gestion RDV, facturation…) | Avant G3 | ☐ |
| 2.4 | **DPA** signés avec chaque sous-traitant (Scaleway, Stripe, GoCardless, Yousign, Brevo, OctoPush, FCM, PostHog) | Avant G3 | ☐ |
| 2.5 | **Politique de confidentialité** + mentions d'information patients | Avant G3 | ☐ |
| 2.6 | Gestion des **droits** : accès, rectification, effacement (dans les limites de rétention médicale), **portabilité (art. 20)** | Avant G3 | ☐ |
| 2.7 | **Minimisation** : ne collecter que le nécessaire ; pas de PII dans logs/push/SMS/email | Dès le code | ◐ |
| 2.8 | **Consentements** tracés et révocables (`consent_record`) | Dès le code | ◐ |
| 2.9 | **Journal d'accès** au dossier patient (`audit_log` append-only) | Dès le code | ◐ |
| 2.10 | Procédure **violation de données** (notification CNIL < 72 h) | Avant G3 | ☐ |
| 2.11 | **Transferts hors UE** : aucun pour la donnée de santé ; vérifier chaque prestataire | Étape 0 | ☐ |
| 2.12 | Attention **PostHog** : masquage PII dans session replays, autocapture désactivée sur champs santé, hébergement **EU Cloud** | Dès l'intégration | ☐ |

---

## 3. AIPD (Analyse d'Impact relative à la Protection des Données)

| # | Item | Quand | Statut |
|---|---|---|---|
| 3.1 | **Lancer l'AIPD** (obligatoire : traitement de données de santé à grande échelle) | **Étape 0** (avant tout dev sur donnée réelle) | ☐ |
| 3.2 | Décrire finalités, données, flux, durées de conservation | Étape 0 | ☐ |
| 3.3 | Évaluer risques (confidentialité, intégrité, disponibilité) + mesures | Étape 0-1 | ☐ |
| 3.4 | **Validation par le DPO** | Avant G3 | ☐ |
| 3.5 | Revue de l'AIPD à chaque nouvelle fonction sensible (ex. future IA Scribe) | Continue | ☐ |

> L'AIPD doit être **validée avant le développement** de toute fonction touchant aux données de santé en prod (contrainte du brief, confirmée).

---

## 4. Secret médical & cloisonnement (R.4127-72 CSP)

| # | Item | Quand | Statut |
|---|---|---|---|
| 4.1 | **RBAC** : le secrétariat n'accède pas au contenu clinique | Dès le code | ◐ |
| 4.2 | **RLS** multi-tenant : aucune fuite inter-cabinets (testée) | Dès le code | ◐ |
| 4.3 | **Chiffrement colonne** des données médicales (clé par cabinet, KMS) | Dès le code | ◐ |
| 4.4 | **Scrubbing des logs** (NER + regex) vérifié en CI | Dès le code | ☐ |
| 4.5 | Cloisonnement de la **messagerie triadique** (scopes) | Étape 3 | ☐ |
| 4.6 | **Proches / ayants droit** (US-P30) : autorité parentale tracée, accès révocable à la majorité, AIPD à étendre aux mineurs | Avant feature | ☐ |
| 4.7 | **Vérification RPPS/ADELI** (annuaire ANS) avant de **lister** un `provider` — anti-usurpation (`05` §10.6, `11` §13) | Avant annuaire public | ☐ |
| 4.8 | **Recherche unifiée back-office V2** : résultats filtrés par **RLS + RBAC** (un secrétaire n'atteint jamais le clinique via la recherche/l'assistant) | Avec V2 | ☐ |

---

## 5. eIDAS — signature électronique

| # | Item | Quand | Statut |
|---|---|---|---|
| 5.1 | Signature **niveau avancé (AES)** via Yousign (backup Universign) | Étape 2 | ☐ |
| 5.2 | **Archivage probant** des documents signés (intégrité sha256 + horodatage) | Étape 2 | ☐ |
| 5.3 | Tiers-archiveur à valeur probante pour conservation longue | Avant scale | ☐ |
| 5.4 | **Délai de rétractation 14 jours** sur actes esthétiques géré dans le workflow | Selon périmètre | ☐ |
| 5.5 | Devis signé **immuable** (verrouillage + 409 sur modif) | Étape 2 | ◐ |

---

## 6. Paiement

| # | Item | Quand | Statut |
|---|---|---|---|
| 6.1 | **PCI-DSS délégué** à Stripe (jamais de numéro de carte chez nous) | Étape 2 | ☐ |
| 6.2 | Mandats **SEPA** conformes via GoCardless | Étape 2 | ☐ |
| 6.3 | Webhooks paiement **vérifiés (signature)** et **idempotents** | Étape 2 | ☐ |
| 6.4 | Facturation & mentions légales conformes | Étape 2 | ☐ |
| 6.5 | (Post-MVP) Alma : cadre du financement, rev-share, information précontractuelle | Post-MVP | ☐ |

---

## 7. AI Act (UE) — pour quand l'IA arrivera (post-MVP)

> **Au MVP : pas d'IA décisionnelle** (ADR-009). Cette section s'active avec l'IA Scribe / le triage IA. À garder en tête car structurant.

| # | Item | Quand | Statut |
|---|---|---|---|
| 7.1 | Classer le système (Scribe = vraisemblablement **haut risque**) | Avant dev IA | ☐ |
| 7.2 | Calendrier : obligations haut risque repoussées par le **Digital Omnibus** — Annexe III **2 déc. 2027**, IA embarquée produits régulés **août 2028** ; dispositifs médicaux ≈ **août 2027**. Vérifier la date liante à la publication au JO | Veille | ☐ |
| 7.3 | Système de **gestion des risques** + **gouvernance des données** | Avant dev IA | ☐ |
| 7.4 | **Journalisation**, **supervision humaine**, **documentation technique** | Avant dev IA | ☐ |
| 7.5 | **Validation humaine item-par-item** + score de confiance (déjà prévu) | Avant dev IA | ☐ |
| 7.6 | Conservation audio Scribe **7 jours max** sauf opt-in séparé | Avant dev IA | ☐ |
| 7.7 | Consentement patient **explicite et révocable** pour l'IA (`consent_record purpose='ia_scribe'`) | Avant dev IA | ☐ |

---

## 8. MDR — risque « dispositif médical » 🚨

> Angle mort n°1 du brief (cf. `01` §6.3). **Décision : rester hors périmètre DM au MVP** pour éviter marquage CE + ISO 13485 (chantier de plusieurs mois/années).

| # | Item | Statut |
|---|---|---|
| 8.1 | **Exclure** toute vérification d'interactions médicamenteuses du MVP | ☑ (décidé, ADR-009) |
| 8.2 | **Exclure** l'aide à la prescription / décision diagnostique ou thérapeutique | ☑ (décidé) |
| 8.3 | **Exclure** le triage clinique automatisé ; le triage messagerie reste de la **priorisation visuelle par règles** | ☑ (décidé) |
| 8.4 | Le Scribe (post-MVP) se limite à la **transcription/résumé descriptif** non décisionnel en phase 1 | ☐ |
| 8.5 | Refaire une **analyse de qualification DM** (règle 11 MDR) avant toute feature à coloration décisionnelle | ☐ |
| 8.6 | **Écran Ordonnance** (maquette hi-fi) : le **blocage automatique allergie/interactions** et la **suggestion d'alternative** sont **EXCLUS** du MVP. L'API **affiche** les allergies saisies (lecture passive), ne **contrôle** rien automatiquement, ne **suggère** aucune thérapeutique. La signature eIDAS + PDF restent OK (`05` §10.5, `06` E4.8) | ☑ (décidé) |
| 8.7 | **Assistant « Demander à Nubia »** (back-office V2) : **organisationnel/administratif uniquement** (RDV, encaissements, relances) ; **aucune aide à la décision clinique ni diagnostic** ; **humain dans la boucle** ; IA **souveraine** ; **post-traction** (`05` §10.8, `06` E7.2, `../design/08`) | ☐ |

> Rappel juridique : un logiciel qui alerte sur des interactions, suggère une posologie ou oriente une décision thérapeutique est qualifiable **dispositif médical** (MDR règle 11, classe IIa-III → marquage CE + ISO 13485).

---

## 9. Identité & interopérabilité (Ségur — post-MVP)

| # | Item | Quand | Statut |
|---|---|---|---|
| 9.1 | **INS** (Identifiant National de Santé) — traité comme PII critique (chiffré) | Modèle dès J0, usage Ségur plus tard | ◐ |
| 9.2 | **Pro Santé Connect** (e-CPS) — homologation ANS (~2 mois + dev) | Avant Ségur | ☐ |
| 9.3 | **France Connect** patient | Post-MVP | ☐ |
| 9.4 | **MSSanté** (échanges entre pros) | Post-MVP | ☐ |
| 9.5 | **FHIR R4** (DMP / Mon Espace Santé) | Post-MVP | ☐ |
| 9.6 | **Référencement Ségur Vague 2/3** (financement État) | Phase scale | ☐ |

> Ne bloque pas le MVP sur Ségur/PSC (cf. `01` §3.4). Le modèle de données prévoit déjà l'INS et les champs nécessaires pour ne pas créer de dette.

---

## 10. Sécurité applicative & audits

| # | Item | Quand | Statut |
|---|---|---|---|
| 10.1 | TLS partout, HSTS, en-têtes de sécurité | Dès le code | ◐ |
| 10.2 | MFA sur comptes cabinet ; rate limiting `/auth` | Étape 1 | ☐ |
| 10.3 | Antivirus sur uploads | Étape 1 | ☐ |
| 10.4 | Scan dépendances + secrets en CI | Étape 0 | ☐ |
| 10.5 | Secrets hors code (Scaleway Secret Manager) + rotation | Étape 0 | ☐ |
| 10.6 | **Pré-audit / pen-test** ciblé avant le pilote prod | Avant G3 | ☐ |
| 10.7 | Pen-test annuel (quand budget) | Post-levée | ☐ |
| 10.8 | Assurance **RC pro tech santé** | Avant pilote | ☐ |

---

## 11. Récap — la barrière minimale avant G3 (1re donnée patient réelle)
Avant de basculer un vrai cabinet sur des données réelles, ces éléments doivent être ☑ :
1. Hébergement **HDS** contractualisé (1.1-1.3).
2. **AIPD validée** par le DPO (3.4).
3. **DPA** signés avec tous les sous-traitants (2.4).
4. **Registre des traitements** + politique de confidentialité (2.2, 2.5).
5. **Chiffrement colonne + RLS + audit append-only + scrubbing logs** effectifs et testés (4.2-4.4).
6. **Sauvegardes + test de restauration** (1.6).
7. Procédure **violation de données** (2.10).
8. **RC pro santé** souscrite (10.8).

> Tant que ces 8 points ne sont pas verts : démo investisseurs OK (données fictives), **pilote prod NON**.

> Décisions techniques associées : `04` (ADR-009, ADR-010). Implémentation chiffrement/rétention/audit : `05` §3, §4, §6.
