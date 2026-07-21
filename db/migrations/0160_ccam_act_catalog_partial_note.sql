-- 0160_ccam_act_catalog_partial_note.sql
-- Documente explicitement que ccam_act (migration 0119) reste un extrait
-- représentatif (~31 actes), PAS la nomenclature CCAM dentaire complète
-- (#4054). L'extension à la nomenclature complète (source CNAM/ameli)
-- nécessite un export officiel machine-readable — recopier des centaines de
-- codes/tarifs à la main dans une migration serait une source d'erreurs
-- silencieuses sur des données de facturation médicale, donc délibérément
-- hors scope tant qu'un fichier source fiable n'est pas fourni.
-- Migrations immuables une fois mergées (db/migrations/README.md) : la
-- correction du commentaire de 0119 passe par une nouvelle migration.

COMMENT ON TABLE ccam_act IS
    'Référentiel CCAM (actes dentaires). Public en lecture, non tenant. '
    '#3226. Extrait représentatif (~31 actes), PAS la nomenclature CCAM '
    'dentaire complète — #4054 : extension bloquée sur un export officiel '
    'CNAM/ameli machine-readable (pas de saisie manuelle de données de '
    'facturation médicale).';
