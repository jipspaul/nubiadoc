-- 0191_sterilized_pouch_code_unique.sql
-- Découvert en implémentant #4139 (écran de scan Datamatrix) : le test
-- attendu ("un code déjà utilisé affiche une erreur") suppose qu'un même
-- code de pochette (datamatrix/barcode) ne peut pas être scanné deux fois
-- — mais sterilized_pouch.code (migration 0190, #4137) n'avait aucune
-- contrainte d'unicité. Une pochette physique porte un identifiant unique
-- (numéro de série imprimé sur l'étiquette de traçabilité) : deux scans du
-- même code dans le même cabinet indiquent soit une double-saisie, soit
-- une pochette déjà utilisée pour un autre acte — les deux doivent être
-- rejetés plutôt que silencieusement dupliqués.
--
-- Unicité scopée au cabinet (pas globale) : deux cabinets utilisant le
-- même fournisseur de sachets peuvent légitimement avoir des codes qui se
-- recoupent (numérotation du fabricant non garantie unique cross-cabinet).

ALTER TABLE sterilized_pouch
    ADD CONSTRAINT sterilized_pouch_cabinet_code_uniq UNIQUE (cabinet_id, code);
