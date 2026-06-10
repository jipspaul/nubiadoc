# Lot E — Compagnon Nubia (GenUI / A2UI) ⭐ [R5]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · **[Direction UX & garde-fous → 02-ux-compagnon-genui.md](02-ux-compagnon-genui.md)** (lecture obligatoire)
> Workstream phare de la V2. Dépend de : M2, M3, M5 (lot A), [lot C](lot-c-ecrans-demo.md) pour E8.

## Détail fonctionnel

Voir **[02-ux-compagnon-genui.md](02-ux-compagnon-genui.md)** pour le concept, l'architecture A2UI et les **garde-fous conformité non négociables** (hors‑MDR, DEMO_MODE, zéro PII). Toute issue de ce lot doit les respecter et les **prouver par test**.

## Backlog atomique

| ID | Titre | Critères d'acceptation | Tests | → |
|----|-------|------------------------|-------|---|
| **E0** | `docs(app): ADR Compagnon GenUI — choix stack A2UI, contrat surface/events, garde-fous conformité (hors-MDR, démo-only, no-PII)` | ADR mergé dans `ARCHITECTURE.md` + arbitrages §4 tranchés | — | — |
| **E1** | `flutter(app): core/ai — client A2UI (transport REST puis WS) + DTO surface/event + feature flag DEMO_MODE` | flag off ⇒ feature invisible ; client parse une surface de test | unit (parse surface, gating flag) | E0 |
| **E2** | `flutter(app): genui — catalogue renderer A2UI→widgets Nubia (whitelist : text, card RDV, card devis, card plan de traitement, liste, boutons d'action)` | composant inconnu ⇒ fallback sûr (pas de crash) | widget + **golden** par composant | E1 |
| **E3** | `flutter(app): CompanionBloc + CompanionChatPage (saisie, historique, rendu surface streaming, disclaimer hors-MDR)` | bandeau disclaimer visible ; états loading/error | bloc + widget | E2 |
| **E4** | `flutter(app): bridge actions GenUI → usecases existants (showAppointments/bookAppointment/showDocuments/explainQuote)` | une action `bookAppointment` appelle `BookAppointmentUseCase` | unit (chaque handler) | E3,A1 |
| **E5** | `flutter(app): Accueil génératif — HomeScreen rend une surface A2UI composée (prochain RDV/à signer/à payer/prévention) + fallback statique` | si agent KO ⇒ fallback `DashboardGrid` actuel | widget (succès + fallback) | E2,M2 |
| **E6** | `flutter(app): tap-card → ouvre compagnon avec prompt pré-rempli (deep link nubia://companion?prompt=…)` | taper « Expliquer » sur carte devis ouvre chat pré-rempli | widget (deep link) | E3,E5 |
| **E7** | `flutter(app): booking conversationnel génératif (wizard motif→cabinet→créneau via surfaces, réutilise BookAppointmentUseCase)` | confirme un RDV de bout en bout (données démo) | widget + unit | E4 |
| **E8** | `flutter(app): explication devis/plan de traitement (surface explicative passive + disclaimers, zéro reco clinique)` | réponses passives ; refus si question médicale (renvoi praticien) | widget (refus garde-fou) | E4,C1 |
| **E9** | `flutter(app): garde-fous Compagnon — refus d'avis médical, redaction PII avant envoi, audit append-only, anti-injection` | prompts médicaux ⇒ message de redirection ; PII masquée dans payload | unit (redaction, refus), widget | E3 |
| **E10** | `flutter(app): seed démo Compagnon (patient Camille, Dr Marin, devis 1 250 €, acompte 380 €) sous DEMO_MODE` | conversation scénarisée reproductible | widget (scénario) | E1 |
| **E11** | `flutter(app): integration test — un flow conversationnel complet (demande → surface → action → confirmation)` | E2E headless vert | integration | E7 |

**Séquence interne** : `E0→E1→E2→{E3,E5}` ; `E3→{E4→{E7,E8}, E6, E9}` ; `E1→E10` ; `E7→E11`.
