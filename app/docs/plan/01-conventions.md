# Conventions, philosophie & Definition of Done

> ⬅️ Retour : [`IMPLEMENTATION_PLAN.md`](../../IMPLEMENTATION_PLAN.md)
> **À lire par tout agent avant de coder une issue, quel que soit le lot.**

## 1. Philosophie de développement

1. **Domain first** — entités + ports avant le moindre pixel.
2. **Test-driven** — chaque use case + règle métier = test unitaire **avant** l'implémentation.
3. **Feature-gated** — chaque nouvelle feature derrière un flag jusqu'au merge sur `main`.
4. **Hexagone strict** — `domain/` n'importe jamais `package:flutter/...`.
5. **Mocks visuels acceptés** — les écrans 🎭 (plan de traitement, passeport, échéancier) ont de vraies pages Flutter avec données statiques.
6. **Conformité by design** — RGPD/HDS, hors‑MDR, données **fictives** tant que la barrière **G3** (`../../../docs/07-conformite.md` §11) n'est pas franchie.

## 2. Gabarit d'une issue atomique

Chaque issue est **indépendamment mergeable**, taillée **≤ 1–2 jours**, et suit ce gabarit :

- **Titre** (prêt à coller) : `flutter(app): <scope> — <résumé impératif>`
- **Périmètre** : fichiers créés/touchés (chemins réels).
- **Critères d'acceptation** : comportement observable.
- **Tests** : unit / widget / golden / integration exigés (la CI `test-integrity` interdit la suppression de tests / `skip`).
- **Dépend de** : autres issues.

> Dispatch : `agents/new-agent.sh` → Forgejo, `label:agent:go` + assignee `flutter-agent`. **Cap 15 issues / batch, 200 ms entre créations.**

## 3. Commandes utiles

```bash
# Dans app/

# Run (dev)
flutter run --dart-define=API_BASE_URL=http://localhost:8080/v1

# Run (démo — données fictives, bypass auth, Compagnon activé)
flutter run --dart-define=API_BASE_URL=http://localhost:8080/v1 --dart-define=DEMO_MODE=true

# Tests unitaires + widget (+ goldens)
flutter test
flutter test --update-goldens   # régénérer les goldens (catalogue GenUI)

# Tests d'intégration (simulateur connecté)
flutter test integration_test/

# Génération de code (injectable, retrofit, json_serializable, l10n)
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n

# Analyse / format
flutter analyze --fatal-infos
dart format lib/ test/

# Build release
flutter build ipa       --dart-define=API_BASE_URL=https://api.nubia.health/v1
flutter build appbundle --dart-define=API_BASE_URL=https://api.nubia.health/v1
```

## 4. Definition of Done (par issue)

- [ ] Code respecte l'hexagone (`domain/` sans Flutter) et « 1 widget = 1 fichier ».
- [ ] `flutter analyze --fatal-infos` vert.
- [ ] Tests exigés écrits **et** verts (unit/widget/golden/integration selon le lot).
- [ ] `test-integrity` vert (aucun test supprimé / `skip` / `#[ignore]`).
- [ ] Pour le Compagnon : garde-fous conformité respectés (hors‑MDR, DEMO_MODE, no‑PII) **vérifiés par test**.
- [ ] Commit FR à l'impératif + `Co-authored-by` ; PR vers `main` ; CI verte avant merge humain.
- [ ] `PROGRESS.md` mis à jour si décision structurante (lot E surtout).
