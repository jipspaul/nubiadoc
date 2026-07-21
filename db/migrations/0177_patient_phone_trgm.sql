-- 0177_patient_phone_trgm.sql
-- Index trigram sur le téléphone patient (#4100) : pg_trgm existe déjà sur
-- first_name/last_name (migration 0012) mais pas sur le téléphone,
-- empêchant une recherche rapide par numéro à l'accueil.
--
-- `patient` n'a pas de colonne `phone` à plat — le téléphone vit dans
-- `contact jsonb` (`contact->>'tel'`, migration 0003, commentaire "email,
-- tel, adresse"). Index d'expression GIN trigram sur ce chemin JSONB, même
-- opclass que les index existants (gin_trgm_ops, extension déjà activée).

CREATE INDEX patient_phone_trgm
    ON patient USING gin ((contact->>'tel') gin_trgm_ops);
