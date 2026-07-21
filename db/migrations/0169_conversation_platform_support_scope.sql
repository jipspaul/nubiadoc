-- 0169_conversation_platform_support_scope.sql
-- Autorise les conversations sans patient pour un futur canal de support
-- cabinet ↔ Nubia (#4168, "Support comme produit" §4.2).
--
-- Écart assumé par rapport à l'issue (documenté ici + dans le commentaire
-- de la PR/issue, pas une décision silencieuse) :
--
-- 1) `conversation.patient_id` N'EST PLUS NOT NULL depuis la migration 0036
--    (issue #450, "la liaison clinique peut arriver après la prise de
--    contact") — cette migration ne rend donc PAS la colonne nullable
--    (déjà fait), elle ajoute une contrainte sur le nouveau scope.
--
-- 2) Le CHECK demandé par l'issue tel quel —
--      CHECK ((scope = 'platform_support') = (patient_id IS NULL))
--    — est un CHECK BIDIRECTIONNEL : il casserait DEUX comportements
--    existants et testés (pas des bugs, des décisions produit déjà
--    shippées) :
--      a. scope='patient_pharmacy' n'a JAMAIS patient_id renseigné (seulement
--         patient_account_id/pharmacy_id, migration 0126,
--         db/tests/45_conversation_pharmacy_rls.sql).
--      b. scope='patient_cabinet' AVEC patient_id NULL est un état
--         intermédiaire volontaire ("liaison clinique différée", #450) :
--         une conversation peut être créée avant que le lien vers la fiche
--         patient clinique existe, puis backfillée (`messaging.rs`,
--         `ON CONFLICT DO UPDATE SET patient_id = EXCLUDED.patient_id`) —
--         testé explicitement par db/tests/051_conversation_patient_account_rls.sql
--         et db/tests/29_conversation_create.sql.
--    Le second test demandé par l'issue ("scope='patient_cabinet',
--    patient_id=NULL → doit échouer") CONTREDIT DIRECTEMENT ce comportement
--    déjà shippé — l'implémenter casserait #450 en silence. Ce n'est pas
--    implémenté : décision produit à trancher explicitement (arbitrer entre
--    #450 et cette issue), pas un choix technique unilatéral.
--
-- Ce qui EST implémenté, sans rien casser : la garantie utile réellement
-- demandée par l'issue — un scope platform_support ne peut PAS avoir de
-- patient_id (sens unique). Ça suffit à débloquer la création de
-- conversations de support sans patient.

ALTER TABLE conversation
    ADD CONSTRAINT conversation_platform_support_no_patient_chk
    CHECK (scope <> 'platform_support' OR patient_id IS NULL);

COMMENT ON CONSTRAINT conversation_platform_support_no_patient_chk ON conversation IS
    'scope=platform_support => patient_id NULL (sens unique — la réciproque '
    'casserait la liaison clinique différée de #450, cf. commentaire de '
    'migration). Issue #4168.';
