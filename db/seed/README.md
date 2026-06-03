# `db/seed/` — Jeu de données démo (à écrire)

> Données **fictives uniquement**. ⚠️ **Aucune donnée patient réelle avant la barrière G3** (`../../docs/07` §11). Chargé par le rôle `nubia_seed`, jamais en prod sur données réelles.
> **Statut : spécification** — le SQL/script de seed est à écrire après les migrations.

## Objectif
Alimenter la **démo investisseurs** (les 12 rubriques du PDF, mockées 🎭) et les **tests e2e** avec un cabinet crédible. Idempotent (rejouable).

## Contenu cible (cohérent avec les maquettes `../../design/mockups/`)
- **Cabinet** : « Cabinet Lyon » (dentaire), horaires + infos pratiques (`settings`), 1 établissement géolocalisé (Lyon 2e).
- **Membres** : Dr Hugo Marin & Dr Claire Lefèvre (`practitioner`, RPPS fictif **vérifié**), Sonia à l'accueil (`secretary`), 1 `admin`.
- **Annuaire** : `provider` listés (verified) avec spécialités, secteur, langues, PMR, créneaux ouverts (`availability_slot`).
- **Patients** (fictifs) : Marc Dubois (plan implantaire 26, allergie latex), Camille Rousseau (devis à signer 2 060 €), Karim Saïdi (urgence, allergie pénicilline), + quelques autres ; un `patient_account` titulaire avec **proches** (Léo, Jade).
- **RDV** : journée type (agenda rempli, 1 en retard, 1 au fauteuil, file d'attente).
- **Wedge** : 1 devis `sent` (→ signature), 1 `signed` + acompte `paid`, 1 `draft`.
- **Clinique** : odontogramme de Marc Dubois, journal clinique (notes globales + liées à un acte), plan de traitement 3 phases.
- **Messagerie** : 2 fils urgents (priorisation visuelle), 1 normal.
- **Couverture** : régimes variés (Régime général / AME / CSS), 1 mutuelle (MGEN), tiers payant activé.

## Règles
- **Zéro PII réelle**, noms/numéros inventés (RPPS, n° sécu fictifs).
- **Chiffrement** : les champs sensibles (n° sécu, notes, messages) passent par le **même chemin applicatif** que la prod (le seed clinique chiffré se fait via un petit binaire/commande `nubia` plutôt qu'en SQL brut, pour ne pas court-circuiter `core/crypto`).
- Montants en `numeric(12,2)` (centimes côté API). Dates réalistes proches de « aujourd'hui ».
- Rejouable : `TRUNCATE … RESTART IDENTITY CASCADE` puis insert, ou upsert idempotent.

> Modèle : `../../docs/05`. Écrans de référence : `../../design/mockups/README.md`. Barrière prod : `../../docs/07` §11.
