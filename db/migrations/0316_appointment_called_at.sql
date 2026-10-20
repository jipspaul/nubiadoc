-- 0316_appointment_called_at.sql
-- Horodatage de l'appel réel du patient (`POST .../call-next`) sur
-- appointment — jusqu'ici seul `started_at` (début de séance via
-- `POST .../start`) était tracé, distinct de l'instant d'appel. Sans cet
-- horodatage, l'indicateur « Retard sur le planning » de la maquette
-- design-v2 salle d'attente (`starts_at` vs heure d'appel réelle) est
-- non calculable (#8182).

ALTER TABLE appointment
    ADD COLUMN called_at timestamptz;

COMMENT ON COLUMN appointment.called_at IS
    'Horodatage du passage en file via POST .../call-next (#8182) — distinct '
    'de started_at (début de séance effective via POST .../start).';
