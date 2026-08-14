-- 0228_patient_created_by_secretariat.sql
-- Corrige le dead-end #5428 : `quick_create_patient` (accueil walk-in,
-- clinical.rs) insère un patient sans AUCUN appointment — la garde R10
-- (#3821/#3823, `list_cabinet_patients`/`get_cabinet_patient`) exige un
-- appointment actif avec un praticien du secrétariat pour qu'une secrétaire
-- voie le patient, donc le dossier qu'elle vient elle-même de créer lui est
-- immédiatement invisible (liste + 404 détail) tant qu'aucun RDV n'existe.
-- Trace la secrétariat créateur au moment du walk-in pour que la garde R10
-- puisse aussi matcher sur cette origine, sans affaiblir le cloisonnement
-- (toujours scopé secrétariat, pas un accès patient ouvert).
-- Issue : #5428

ALTER TABLE patient ADD COLUMN created_by_secretariat_id uuid REFERENCES secretariat(id);
