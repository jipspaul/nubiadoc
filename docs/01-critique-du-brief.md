# 01 — Critique du brief existant

> Document de challenge. Objectif : confronter le brief (`INSTRUCTIONS_PROJET.md` + `nubiaDoc.pdf`) à la réalité d'exécution d'une équipe **solo / pré-seed**. Ton volontairement direct, comme demandé. Ce n'est pas un jugement sur la qualité de la vision — qui est bonne — mais sur l'**exécutabilité** ici et maintenant.

---

## 0. Verdict en une phrase

Tu as écrit la roadmap d'une scale-up financée à 2,5 M€ avec 12-15 personnes, mais tu vas l'exécuter seul (ou presque) sans financement. **Le brief n'est pas faux, il est hors d'échelle.** Tant qu'on ne tranche pas un *wedge* unique et qu'on ne reporte pas 80 % du périmètre, le projet n'est pas démarrable.

---

## 1. L'écart de réalité fondamental

Le brief s'auto-décrit comme nécessitant :

- **2,5 M€ de seed**, burn 130 k€/mois, équipe **12-15 personnes** (dont 7 tech).
- **~150-200 k€ de compliance à débourser *avant la première facture*** (HDS, DPO, pen-test, avocat santé, assurance RC pro).
- **18 mois** pour un MVP couvrant 7 piliers.

En contexte solo/pré-seed, ces trois chiffres sont des murs, pas des objectifs :

| Hypothèse du brief | Réalité solo/pré-seed | Conséquence |
|---|---|---|
| 7 devs en parallèle | 1 dev (toi) | Le parallélisme des phases s'effondre : ce qui prenait 18 mois à 7 en prend mécaniquement beaucoup plus à 1. |
| 150-200 k€ compliance avant 1er € | Runway perso limité | La certification HDS applicative + DPO + avocat santé = barrière à l'entrée que tu ne peux pas payer aujourd'hui. |
| Burn 130 k€/mois | ~0 € de burn | Pas de salaires, pas de consultants CISO 2j/sem, pas d'équipe migration dédiée M+8. |

**Le piège HDS à clarifier tout de suite** : le brief mélange deux choses différentes.
- L'**hébergement HDS** (héberger sur une infra certifiée, ex. Scaleway) est *obligatoire dès la première donnée de santé réelle*. Non négociable, mais accessible : tu prends de l'infra déjà certifiée.
- La **certification HDS de ton entreprise en tant qu'hébergeur** n'est requise que si *tu héberges toi-même*. Si tu restes client d'un hébergeur certifié, tu n'as pas à te faire certifier hébergeur.
- Ce que le brief appelle « audit HDS M+15 » mélange en fait certification, conformité applicative et Ségur. Ce sont trois chantiers distincts. Les confondre, c'est se croire à 15 mois d'un mur qui est en réalité soit (a) franchissable dès J0 par le choix d'hébergeur, soit (b) reportable bien après le MVP.

> **Recommandation #1** — Tant qu'il n'y a pas de vraie donnée patient en production, tu peux développer et démontrer sans la machinerie HDS complète, à condition d'utiliser **uniquement des données fictives**. La conformité « lourde » se déclenche au moment du **premier cabinet pilote réel**, pas au premier commit. C'est ce décalage qui rend le projet démarrable seul.

---

## 2. Incohérence interne entre tes deux documents

C'est le point le plus important et il vient de tes propres fichiers.

- **`nubiaDoc.pdf`** décrit une **application patient dentaire** : 13 rubriques (RDV, messagerie, dossier admin/médical, signature, notifications, espace financier, plan de traitement, passeport implantaire, suivi/prévention, tableau de bord, coffre-fort, infos cabinet, fonctions avancées). C'est cadré, réaliste, vendable, et centré sur **un seul utilisateur** : le patient.
- **`INSTRUCTIONS_PROJET.md`** décrit une **plateforme tout-en-un anti-Doctolib** : app patient *+ logiciel métier praticien + hub secrétariat + IA Scribe + analytics ML + parcours de soins en réseau + Mon Espace Santé + marketplace*. Trois types d'utilisateurs, 7 piliers, IA souveraine self-hosted.

**Ce ne sont pas le même projet.** Le PDF est un excellent **Périmètre 1** (6-9 mois réaliste). Le MD est la **vision à 5 ans**. Les traiter comme un seul cahier des charges est la source numéro un du sur-dimensionnement.

> **Recommandation #2** — Adopter le PDF comme socle du MVP réel, et reléguer le MD au rang de *vision document* / *north star*. La découpe projet (doc 02) part de cette décision.

---

## 3. Critique de la stack technique (mode très critique)

Principe directeur : **chaque brique d'infra que tu ajoutes est une brique que tu dois opérer, monitorer, sécuriser et débugger seul, à 3h du matin, sur une app de santé.** Le bon réflexe pré-seed n'est pas « quelle est la meilleure techno », c'est « quelle est la techno qui me coûte le moins d'attention pour la valeur rendue ».

### 3.1 Frontend — Flutter partout (décision : un seul écosystème)

**Décision retenue : Flutter pour l'app patient ET le back-office praticien/secrétariat.** Un seul langage (Dart), un seul écosystème, un seul pipeline. Pour un solo, c'est le choix qui minimise la surface — parfaitement aligné avec le principe directeur de cette critique.

- Flutter pour l'**app patient mobile** : **bon choix**, validé. Codebase unique iOS/Android, accès natif (push, QR, géoloc, biométrie) — exactement le profil du PDF.
- Flutter pour le **back-office praticien/secrétariat** (Flutter Web, ou Flutter Desktop si besoin) : **le SEO est sans objet** sur une app métier authentifiée — l'argument SEO contre Flutter Web ne s'applique donc pas ici. Unifier sur Dart évite de maintenir **deux écosystèmes en parallèle**, ce qui est le bon arbitrage en solo.
- Le brief proposait Next.js pour le back-office : abandonné. La PWA web patient de fallback (QR sans app) peut rester un petit Flutter Web embarqué, pas une stack séparée.
- ⚠️ **Le seul vrai arbitrage qui demeure** (et il n'a rien à voir avec le SEO) : Flutter Web est moins à l'aise que React/Next sur les **UI très data-dense** (tableaux/agendas multi-colonnes, sélection de texte, impression) et son **poids de chargement initial** est plus lourd. Mitigations : rendu **CanvasKit**, lazy-loading, et — si le back-office devient un vrai tableur lourd — l'option **Flutter Desktop** (app installée au cabinet) qui efface le souci de perf web.
- 💡 **Arbitrage MVP** : commence par **une seule cible** (l'app patient), le back-office Flutter peut démarrer minimaliste (voire un admin générique au tout début) et se polir ensuite. Tu n'as pas besoin des deux fronts finis simultanément.

### 3.2 Backend — la sur-ingénierie est ici

Le brief empile : **NestJS (monolithe modulaire) + microservices Python FastAPI + Temporal.io + NATS JetStream + Socket.IO + extraction Go en Phase 2**. Pour du pré-seed, c'est 4 paradigmes d'exécution distincts.

- ✅ **Monolithe modulaire** : bon choix de structure, garde-le. **Langage retenu : Rust / Axum** (révision 06/2026, cf. `04` ADR-002), en remplacement de NestJS/Node — l'équipe maîtrise déjà Rust et Dart, et le besoin de WebSockets + forte concurrence (cap ~1M users) joue pour Tokio. C'est *le* bon niveau de structure, avec un langage déjà su.
- ❌ **Temporal.io dès le MVP** : non. Temporal est excellent mais c'est un serveur de plus à opérer. Les workflows (relances no-show, échéanciers, audit) tiennent parfaitement avec **apalis sur le Redis que tu as déjà**. Temporal devient pertinent quand les workflows deviennent vraiment longs/complexes — pas avant.
- ❌ **NATS JetStream** : redondant avec Redis/apalis au début. Une file suffit. Supprime.
- ❌ **Microservices Python FastAPI** : seulement nécessaires pour l'IA (Scribe), qui est Phase 4 (M12+ dans le brief). Tant qu'il n'y a pas d'IA self-hosted, **pas de second runtime**. Quand l'IA arrive, un seul service Python suffit.
- ✅ **Temps réel WebSockets** : besoin confirmé, et Axum/Tokio les fournit nativement, sans serveur ni techno en plus. Pas besoin de Socket.IO. Fan-out multi-instances via pub/sub Redis quand il y aura plusieurs instances.
- ❌ **Go en Phase 2** : l'idée d'extraire le temps réel en Go disparaît — avec Rust, le temps réel performant est déjà dans le monolithe. Rien à réécrire.

> **Backend MVP réaliste** : Rust/Axum + PostgreSQL + Redis (cache + apalis) + Object Storage. Point. Tout le reste se rajoute quand un besoin *prouvé* l'exige.

### 3.3 Data — empilement prématuré

Le brief : **PostgreSQL 16 + pgvector + TimescaleDB + pg_trgm + Redis + Meilisearch + NATS + Object Storage**.

- ✅ PostgreSQL 16 + Redis + Object Storage : socle correct.
- ❌ **Meilisearch** : `pg_trgm` (extension Postgres) couvre la recherche floue des premiers mois sans serveur supplémentaire. Meilisearch viendra si/quand la recherche devient un vrai produit.
- ❌ **TimescaleDB pour l'audit log** : une simple table Postgres partitionnée (par mois) en append-only fait le travail pour des années. TimescaleDB est une optimisation, pas un prérequis de conformité.
- ⚠️ **pgvector** : seulement utile pour les features sémantiques IA → arrive avec l'IA, pas avant.

> **Data MVP réaliste** : PostgreSQL 16 (avec `pg_trgm`, partitioning natif, RLS, chiffrement colonne) + Redis + Object Storage HDS.

### 3.4 Auth & identité — lourd pour du solo

- ❌ **Keycloak self-hosted** : un serveur d'identité critique à opérer et patcher soi-même, sur une app santé, en solo = surface de risque énorme. Préfère une **auth managée** ou une lib intégrée (ex. auth dans l'API Axum via `jsonwebtoken` + `argon2`, ou provider managé) au début.
- ⚠️ **Pro Santé Connect (e-CPS)** : *obligatoire pour Ségur*, mais Ségur est un chantier Phase 5. Homologation ANS = ~2 mois + dev. **Ne bloque pas le MVP dessus.** Tu peux authentifier les praticiens classiquement et brancher PSC quand tu vises le référencement Ségur.
- ⚠️ **France Connect patient** : intégration non triviale et non indispensable au pilote. Email + MFA suffit pour démarrer.

### 3.5 IA — le poste de coût le plus prématuré

- ❌ **Whisper Large v3 self-hosted sur GPU H100 Scaleway** : un H100 coûte plusieurs **milliers d'€/mois**. Provisionner du GPU avant d'avoir un seul client payant est la pire dépense pré-seed possible. Et c'est de toute façon Phase 4.
- ⚠️ Le positionnement « IA souveraine, pas OpenAI/Anthropic, Mistral + Scaleway » est un **choix marketing légitime** — mais il n'impose pas le self-hosting. **Mistral via API managée Scaleway** donne la souveraineté sans la facture GPU ni l'ops.
- 🚨 **Surtout** : l'IA Scribe + la vérification d'interactions médicamenteuses ne sont pas qu'un défi technique, ce sont des **chantiers réglementaires lourds** (voir §6). À reporter franchement.

### 3.6 Infra & observabilité — un métier à plein temps que tu n'as pas

Le brief : **Kubernetes (Scaleway Kapsule) + ArgoCD + Terraform + Vault + Grafana/Prometheus/Loki/Tempo self-hosted + Sentry self-hosted**.

C'est la *stack d'une équipe Platform Engineering*. En solo, chaque élément self-hosted est du temps volé au produit, pour zéro valeur client perçue.

- ❌ Kubernetes Kapsule en solo : commence par un **PaaS conteneurs managé** (Scaleway Serverless Containers / VM + Docker Compose). K8s quand tu auras des gens pour l'opérer.
- ❌ Observabilité self-hosted (Grafana/Prometheus/Loki/Tempo) : prends du **managé** (Scaleway Cockpit, Grafana Cloud, etc.).
- ✅ **PostHog (managé, EU Cloud)** en lieu et place de Sentry : un seul outil pour **analytics produit + session replay + error tracking**, hébergé en UE pour la souveraineté. Évite d'opérer un Sentry/observabilité maison.
- ⚠️ Vault → **Scaleway Secret Manager** managé (le brief le propose déjà en alternative : prends celle-là).
- ✅ Terraform + GitHub Actions : OK, légers et utiles tôt.

> **Règle pré-seed** : *« managé par défaut, self-hosted seulement si la souveraineté l'exige et que tu peux l'opérer »*. Scaleway managé coche déjà la case souveraineté pour la plupart des briques.

---

## 4. Critique du périmètre produit (les 7 piliers)

Les 4 piliers fondateurs + 3 stratégiques + améliorations transversales représentent **chacun un mini-produit**. À eux seuls, certains sont des entreprises entières :

- **Pilier 4 (IA Scribe vocal médical)** = c'est littéralement le produit de Nabla. Le faire en side-feature est irréaliste, et réglementairement risqué (§6).
- **Pilier 1 (check-in multimodal)** : QR + borne tablette + géofencing 200m + file d'attente virtuelle + fallback SMS + mode PMR. Énorme complexité pour une valeur *early* marginale (un cabinet dentaire de 2 praticiens n'a pas une salle d'attente de gare).
- **Pilier 5 (analytics ML no-show, benchmark inter-cabinets, détection sous-cotation CCAM)** : nécessite de la **donnée que tu n'as pas encore**. Le ML no-show sans historique = impossible. À reporter par construction.
- **Pilier 6 (parcours de soins en réseau, téléexpertise)** : effet réseau → ne vaut rien tant que tu n'as pas le réseau. Poule et œuf.

**Le vrai wedge (mon avis tranché)** : sur le dentaire, la douleur aiguë et solvable la plus monétisable est le **couple devis → signature → acompte/financement** (Pilier 2) *adossé à l'app patient du PDF*. C'est :
- un vrai pain (les devis dentaires/ortho/implanto sont chers, longs à signer, à relancer) ;
- directement lié au **cash du cabinet** (donc on paie pour ça) ;
- techniquement borné (Yousign + Stripe + un échéancier) ;
- sans dépendance IA ni Ségur ni réseau.

> **Recommandation #4** — MVP = **app patient (PDF) + RDV en ligne + devis/signature/acompte**. Tout le reste (check-in géofencé, Scribe IA, analytics, parcours réseau, Mon Espace Santé) part en roadmap explicitement datée « post-traction ».

> **⚠️ Override fondateur (décision du 01/06)** — Pour la **démo investisseurs**, l'app patient doit montrer **l'intégralité des rubriques 1-12 du PDF**, quitte à en **mocker** une partie (plan de traitement, passeport implantaire, suivi, échéanciers). Seule la **section 13 (fonctionnalités avancées)** est exclue, hormis « paiement en ligne » conservé via le wedge. Cette décision prime sur le « defer » technique ci-dessus *pour ce qui est montré à l'écran*, **mais pas pour la prod** : un écran mocké reste sur données fictives jusqu'à la conformité HDS du pilote. Détail du marquage prod/démo dans `02-decoupe-projet.md` (WS3 + Jalon Démo).

---

## 5. Critique du business plan et des chiffres

Les cibles M+18 sont posées comme des certitudes alors que ce sont des hypothèses optimistes.

- **LTV/CAC > 40x** : irréaliste. Un excellent SaaS B2B vise 3-5x. 40x signalerait qu'on sous-investit massivement en acquisition. Ce chiffre décrédibilise le reste auprès d'un VC qui sait lire.
- **LTV > 60 000 €/cabinet sur 5 ans** avec un ARPU de 110-150 €/mois : 150 € × 12 × 5 = 9 000 €/an × ... ça ne tient que si tu comptes plusieurs praticiens par cabinet *et* tout le transactionnel à plein régime. À expliciter, sinon c'est du wishful thinking.
- **Churn < 2 %/mois, NPS > 50, NRR > 100 %** : ce sont des *objectifs*, pas des données. À présenter comme tels.
- **ARPU 110-150 €** : repose lourdement sur le **transactionnel** (commission 0,5 % acomptes, rev-share financement 25-30 %, lecture mutuelle). Or ce revenu dépend d'un volume qui n'existe pas avant la traction. L'ARPU *réel* des premiers mois ≈ le prix d'abonnement seul (79-99 €).
- **Pricing vs Doctolib** : « moins cher / tout compris » est un bon angle, mais à **valider par des vrais entretiens** de cabinets dentaires (combien paient-ils réellement aujourd'hui, à qui, pour quoi). Ne construis pas un pricing sur une intuition.

---

## 6. Risques réglementaires : un correctement vu, un sous-estimé, un absent

### 6.1 Correctement identifié — HDS
Bien vu dans le principe. Le seul ajustement est la clarification du §1 (hébergement HDS ≠ certification hébergeur ≠ conformité applicative ≠ Ségur). Ne te crois pas obligé de tout faire avant la première ligne de code.

### 6.2 Sous-estimé — AI Act
Le brief dit « conformité AI Act EU 2026, système à risque élevé ». C'est juste sur le principe, mais le calendrier a bougé et la charge est lourde :
- Les obligations « haut risque » étaient prévues pour le **2 août 2026**, mais l'accord politique **Digital Omnibus** reporte les systèmes Annexe III au **2 décembre 2027**, et l'IA embarquée dans des produits régulés (Annexe I, ce qui inclut les dispositifs médicaux) à **août 2028**. Pour les dispositifs médicaux, l'échéance pleine est plutôt **août 2027**.
- Conséquence : un Scribe IA classé « haut risque » t'impose système de gestion des risques, gouvernance des données, journalisation, supervision humaine, documentation technique, conformité formelle. **C'est un chantier de plusieurs mois à temps plein.** → argument de plus pour **reporter l'IA Scribe** hors MVP.

### 6.3 Absent — le risque « dispositif médical » (MDR / marquage CE) 🚨

**C'est le principal angle mort du brief.** Le MD prévoit :
- la **vérification des interactions médicamenteuses** (BCB Dexther) ;
- la **pré-cotation / aide à la décision clinique** via IA ;
- potentiellement la détection de prescriptions verbales.

Or, en droit européen, **un logiciel destiné à fournir des informations servant à une décision diagnostique ou thérapeutique — typiquement alerter sur des interactions médicamenteuses ou suggérer une posologie — est qualifié de dispositif médical**. Sous le règlement **MDR**, ces logiciels relèvent généralement de la **règle 11**, classés de **IIa à III**, ce qui impose **marquage CE + système qualité ISO 13485**. C'est lourd, long et coûteux.

> **Recommandation #6** — Bannir du MVP toute fonction qui pousse vers la qualification dispositif médical : pas de vérif d'interactions médicamenteuses, pas d'aide à la prescription, pas de pré-cotation « décisionnelle ». Reste sur des fonctions **administratives et documentaires** (devis, RDV, coffre-fort, transcription brute non décisionnelle), qui sortent du périmètre DM. Ce choix de design te fait économiser potentiellement *des années*.

### 6.4 Autres absences
- **RGAA / accessibilité** : non mentionné. Important légalement et éthiquement pour une app santé grand public.
- **PRA/PCA (plan de reprise/continuité)** et **résidence des sauvegardes** : non traités. Une app santé doit pouvoir prouver sa résilience.
- **SLA & astreinte en solo** : le brief prévoit une astreinte payée M+10. En solo, *tu es* l'astreinte 24/7 — intenable. À intégrer dans la stratégie de recrutement / d'association.
- **Réalité du support client** : qui répond au cabinet pilote quand ça casse pendant une consultation ? À designer avant le pilote, pas après.

---

## 7. Ce qui est bien vu (pour équilibrer)

Le brief n'est pas naïf, plusieurs instincts sont excellents :

- **Multi-tenant par Row-Level Security PostgreSQL** : très bon réflexe de cloisonnement (même un bug applicatif ne fait pas fuiter entre cabinets).
- **Chiffrement au niveau colonne** + INS traité comme PII critique + **audit log append-only** + **soft-delete avec rétention 20/30 ans** : excellents fondamentaux de conformité, à garder dès le départ car difficiles à rétrofitter.
- **Validation humaine item-par-item de l'IA** + score de confiance : c'est exactement le bon design médicolégal (quand tu feras l'IA).
- **Positionnement souveraineté (Scaleway, Mistral, données hors Cloud Act)** : cohérent et différenciant sur le marché français.
- **Versioning immuable des devis (SHA-256 + horodatage)** : juste et nécessaire.
- Le **séquencement des piliers** est logique *en tant que vision* — le problème n'est pas l'ordre, c'est de croire qu'on fait tout en 18 mois à une personne.

---

## 8. Synthèse des recommandations

1. **Acter le décalage d'échelle** : le brief est une *vision*, pas un plan d'exécution solo. Séparer les deux explicitement.
2. **Choisir le PDF (app patient dentaire) comme socle MVP**, le MD comme north star.
3. **Trancher un wedge unique** : app patient + RDV + devis/signature/acompte.
4. **Dégraisser la stack** : Rust/Axum + Postgres + Redis + Object Storage + Flutter, tout en managé Scaleway. Reporter Temporal, NATS, Python/IA, Meilisearch, TimescaleDB, Keycloak, K8s, observabilité self-hosted.
5. **Reporter explicitement** : IA Scribe, check-in géofencé, analytics ML, parcours réseau, Mon Espace Santé, marketplace, Ségur/PSC.
6. **Bannir du MVP tout ce qui qualifie en dispositif médical** (interactions médicamenteuses, aide à la prescription/décision).
7. **Clarifier HDS** : hébergement certifié dès la 1re donnée réelle ; conformité applicative/Ségur plus tard ; dev sur données fictives jusqu'au pilote.
8. **Re-baser les chiffres business** sur des hypothèses validées par entretiens cabinets, pas sur des cibles aspirationnelles.

La suite — comment tout ça se traduit en plan d'exécution — est dans **`02-decoupe-projet.md`**.
