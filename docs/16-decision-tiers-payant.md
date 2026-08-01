# 16 — Décision : fournisseur de tiers payant télétransmis AMO/AMC (#4068)

> Document de décision (pas de code) — issue #4068 : trancher entre (a) contractualiser un accès réseau tiers payant + DRE via un agrégateur existant, (b) coupler cet accès au même middleware FSE choisi pour SESAM-Vitale, (c) différer et rester sur la saisie déclarative actuelle. Recommandation par défaut demandée en l'absence d'arbitrage business/vendeur.

## 1. Problème

Le tiers payant de Nubia est aujourd'hui **purement déclaratif** : `quote_item.amo_part`/`amc_part` sont saisis/estimés à la main, jamais alimentés par un flux réseau vers un organisme complémentaire (Viamedis, Almerys, SP Santé…) ni par un retour NOEMIE automatisé. Cette décision est distincte du choix SESAM-Vitale ([`docs/15`](15-decision-sesam-vitale.md)) mais en dépend souvent : Icanopée, cité côté FSE, propose aussi DPEC/tiers payant — d'où une résolution conjointe possible.

## 2. État réel (vérifié dans le code, 2026-07-31)

- `api/src/cabinet_quote_item_parts.rs` (#4069, #4062) : le remboursement AMO/AMC est **estimé automatiquement à 70 % du tarif de référence**, puis **corrigé manuellement** par le secrétariat via `PATCH /v1/cabinet/quotes/:id/items/:item_id/parts` quand le retour NOEMIE arrive par un canal externe (papier/PDF, pas une API).
- Aucun client réseau vers Viamedis/Almerys/SP Santé ni vers un flux NOEMIE dans `api/src` (voir l'audit de code détaillé dans [`docs/15` §2](15-decision-sesam-vitale.md#2-%C3%A9tat-r%C3%A9el-du-positionnement-nubia-v%C3%A9rifi%C3%A9-dans-le-code-et-les-docs-2026-07-31)).
- `patient_account.tiers_payant` (booléen, `docs/05-modele-de-donnees.md:524`) reflète uniquement l'intention déclarée du patient (mutuelle photographiée recto/verso, activée), pas une connexion réseau active.

## 3. Options évaluées

### 3.1 Agrégateur tiers payant dédié (Viamedis/Almerys/SP Santé…)

Accès réseau contractualisé indépendamment du choix SESAM-Vitale. Avantage : découplé, permet d'avancer sur le tiers payant sans attendre un arbitrage FSE. Inconvénient : un fournisseur de plus à intégrer/maintenir/facturer, alors que ces flux transitent en pratique souvent par le même canal que la FSE (les éditeurs métier posent généralement les deux ensemble).

### 3.2 Coupler au même middleware FSE (Icanopée ou équivalent)

Cohérent si [`docs/15`](15-decision-sesam-vitale.md) retenait un jour l'option (b) (middleware FSE tiers) — un seul contrat, un seul flux technique pour FSE + DPEC/tiers payant. Mais `docs/15` recommande par défaut de **rester hors périmètre V1** pour la FSE : coupler le tiers payant à un fournisseur qui n'est pas encore choisi n'a pas de sens tant que cette première décision n'est pas révisée.

### 3.3 Différer, rester sur la saisie déclarative actuelle

Aucun développement réseau. Le flux existant (estimation 70 % + correction manuelle au retour NOEMIE papier) continue de fonctionner — imparfait (délai, erreur de saisie possible) mais opérationnel, sans dépendance externe ni coût récurrent.

## 4. Recommandation

**(c) Différer, rester sur la saisie déclarative actuelle**, pour les mêmes raisons que [`docs/15`](15-decision-sesam-vitale.md) et par cohérence directe avec elle : (a) engagerait un fournisseur et un coût récurrent sans qu'aucun signal business ne le justifie ; (b) est prématuré tant que le choix FSE lui-même reste hors périmètre V1.

**Justification** :
- Le flux actuel (#4062/#4069) n'est pas cassé — il produit une estimation raisonnable (70 %) et un mécanisme de correction a posteriori déjà en place et audité (`audit_log`).
- Contractualiser un agrégateur tiers payant sans avoir tranché le fournisseur FSE risquerait de dupliquer l'intégration si le choix FSE ultérieur (Icanopée ou équivalent) couvre déjà DPEC/tiers payant nativement.
- Aucun cabinet pilote n'a signalé l'absence d'automatisation du tiers payant comme un point de blocage à l'adoption de Nubia à ce jour.

**Critères de révision** (déclencheurs pour rouvrir cette décision) :
1. [`docs/15`](15-decision-sesam-vitale.md) est révisée vers l'option (b) middleware FSE tiers — réévaluer alors le couplage DPEC/tiers payant du même fournisseur.
2. Un volume significatif d'erreurs/retards de correction manuelle (mesurable via `audit_log` sur `cabinet_quote_item_parts`) rend le coût de la saisie manuelle supérieur à celui d'un agrégateur dédié.
3. Un prospect/client signale explicitement l'absence de tiers payant automatisé comme bloquant.

**Non-décision volontaire** : ce document ne contractualise aucun fournisseur, ne précise ni coût ni périmètre NOEMIE/DRE final — conformément à l'issue, il documente une recommandation par défaut (différer) à rejouer dès qu'un des critères ci-dessus se matérialise.
