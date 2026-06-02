# Flux — Wedge : devis → signature → acompte

> Le parcours le plus structurant et le plus vendeur (démo). Couvre **US-D03, US-D04, US-D05** (praticien) et **US-P19, US-P21, US-P22** (patient), + alerte cabinet (SSE).
> Objectif UX : **zéro friction** entre « je vois mon devis » et « c'est signé et payé ».

## Acteurs & objectif
- **Praticien** : chiffrer un plan de soins et l'envoyer en 1 minute.
- **Patient** : comprendre le coût (et le reste à charge), signer et payer l'acompte sans se déplacer.
- **Cabinet/Secrétariat** : être alerté en temps réel quand c'est signé/payé (facture générée).

## Parcours nominal

### Côté praticien (back-office)
1. **Fiche patient → « Nouveau devis ».**
2. **Ajout des lignes** : acte, code CCAM, dent, montant, parts AMO/AMC. Le **total** et le **reste à charge estimé** se recalculent en direct.
3. **Vérification** → « Envoyer au patient ». Le devis passe `sent` (brouillon versionné tant que non signé). Notification push au patient (sans donnée de santé).

### Côté patient (app mobile) — le money-shot
4. **Notification** « Un devis vous attend » → ouverture de l'app.
5. **Écran Devis** : montant total bien lisible, **reste à charge mis en avant**, détail des lignes repliable, statut `À signer`. CTA primaire **« Signer le devis »**.
6. **Signature électronique** in-app (eIDAS avancé) + consentement explicite. À la signature : devis `signed`, **immuable** (SHA-256 + horodatage).
7. **Acompte** : écran paiement, montant d'acompte, **Apple/Google Pay** ou CB. CTA **« Payer l'acompte »**.
8. **Confirmation** : « Devis signé et acompte payé », reçu disponible dans le coffre-fort, proposition de **prochain RDV**.

### Côté cabinet (temps réel)
9. **Alerte SSE** au back-office : `quote.paid` → badge + **facture générée**. Le secrétariat voit l'acompte encaissé.

## États & cas limites (à designer)
- **Brouillon** : le praticien peut sauvegarder et reprendre ; modifier un devis `signed` est **impossible** (message clair, créer une nouvelle version).
- **Signature interrompue** : reprise possible, le devis reste `sent`.
- **Paiement échoué/refusé** : message clair + « Réessayer » + autre moyen ; le devis reste `signed`, l'acompte `pending`.
- **Hors-ligne** : afficher le devis en lecture seule, signaler que la signature/paiement nécessite une connexion.
- **Devis expiré** : statut `expired`, CTA « Demander un nouveau devis ».
- **Reste à charge = 0** : adapter la formulation (rien à avancer).

## États vides / chargement
- Pas de devis : état vide « Aucun devis pour le moment » + explication.
- Chargement paiement : bouton en état `loading`, non cliquable, annoncé au lecteur d'écran.

## Accessibilité (US-X01)
- Montants en **chiffres tabulaires**, devise explicite (« 1 250 € »), jamais l'info par la couleur seule (statut = icône + texte).
- Ordre de focus logique (montant → détail → CTA), cibles ≥ 44 px, libellés de bouton explicites (« Signer le devis », pas « OK »).
- Messages d'erreur reliés au champ/action et annoncés.

## Microcopy clé (à affiner en `../05-ux-copy/`)
- CTA : « Signer le devis » → « Payer l'acompte » → (succès) « Voir mon reçu ».
- Réassurance : « Signature sécurisée », « Paiement chiffré », « Vous pourrez télécharger votre reçu ».
- **Aucune promesse clinique** dans la copy (cf. `../../docs/03` §2).

## Wireframe (low-fi) — séquence patient
```
[ Devis ]                 [ Signature ]            [ Paiement ]            [ Succès ]
 Total 1 250 €             Récap + case            Acompte 380 €           ✓ Signé & payé
 Reste à charge 380 €      consentement            ◉ Apple Pay             Reçu dispo
 ─ lignes (repliable)      [ Signer ]              ○ Carte                 Prochain RDV ?
 [ Signer le devis ]                               [ Payer l'acompte ]     [ Voir le reçu ]
```

## Stories couvertes → statut design
US-D03 🎨 · US-D04 🎨 · US-D05 🎨 · US-P19 🎨 · US-P21 🎨 · US-P22 🎨 (maquette patient ci-dessous ; back-office praticien à détailler ensuite).

> Maquette hi-fi du parcours patient : voir la session (rendu inline). Prochaine étape : back-office praticien (création de devis) puis onboarding + RDV.
