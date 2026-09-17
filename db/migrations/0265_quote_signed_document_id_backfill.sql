-- 0265_quote_signed_document_id_backfill.sql
-- #7068 : #7046 (migration 0264) pose `quote.document_id` à la signature,
-- mais aucun devis déjà `signed` avant ce correctif n'a jamais eu son PDF
-- généré (`sign_quote` ne touche que la transition `sent -> signed`). Le CTA
-- « Télécharger le devis signé » reste donc invisible sur l'historique
-- (246 devis signés sur 247 dans le parc de démo).
--
-- `enforce_quote_immutable` (migration 0051) bloque toute UPDATE sur une
-- ligne déjà `signed`, y compris pour poser `document_id` — donc un backfill
-- par migration (`UPDATE quote SET document_id = ...`) échouerait ici. On
-- élargit la fonction pour autoriser exactement une mutation : passer
-- `document_id` de NULL à une valeur, sans toucher aucune autre colonne.
-- Le backfill lui-même est fait paresseusement par l'API (`billing::get_quote`,
-- via `generate_quote_document`) à la première lecture d'un devis signé sans
-- document — le PDF est intégralement reconstructible depuis `quote` +
-- `quote_item`, pas besoin de le générer pour les 246 devis d'un coup.

CREATE OR REPLACE FUNCTION enforce_quote_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'signed' OR OLD.signed_at IS NOT NULL THEN
    IF OLD.document_id IS NULL AND NEW.document_id IS NOT NULL
       AND (to_jsonb(NEW) - 'document_id' - 'updated_at')
           = (to_jsonb(OLD) - 'document_id' - 'updated_at') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'quote immuable : modification interdite après signature (id=%)', OLD.id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
