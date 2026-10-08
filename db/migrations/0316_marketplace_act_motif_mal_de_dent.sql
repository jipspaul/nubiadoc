-- 0316_marketplace_act_motif_mal_de_dent.sql
-- #6827 : `GET /v1/search/suggest` n'avait AUCUN acte dont `motifs` couvre les
-- formulations patient les plus courantes (« mal de dent », « carie ») — le
-- mapping besoin→spécialité documenté (`docs/12` §12.1) renvoyait donc trois
-- listes vides sur l'exemple même de la doc, faute de donnée, pas de requête
-- (`marketplace.rs` interroge déjà `motifs`, cf. `list_acts`/`suggest_search`).
-- Acte generaliste (soin conservateur d'une carie) sous Omnipratique, seedé en
-- 0039, motifs couvrant les symptômes patient les plus fréquents.

INSERT INTO medical_act (id, specialty_id, label, motifs) VALUES
  ('d3000000-0000-0000-0000-000000000006', 'd2000000-0000-0000-0000-000000000001', 'Soin d''une carie',
   ARRAY['carie', 'mal de dent', 'rage de dent', 'douleur dentaire', 'HBMD034'])
ON CONFLICT (id) DO NOTHING;
