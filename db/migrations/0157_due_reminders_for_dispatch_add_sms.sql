-- 0157_due_reminders_for_dispatch_add_sms.sql
-- Étend due_reminders_for_dispatch() (migration 0156) au canal SMS — #4036.
--
-- Ajoute `channel` (reminder.channel — jusqu'ici jamais lu : le worker
-- #4034 traitait tout rappel dû comme un push), `phone` (patient_account.phone,
-- nullable) et `sms_opted_in` (notification_preference.sms_rdv — la colonne
-- existait depuis la migration 0024 mais n'était lue par aucun code, cf.
-- issue #4036 : "sms_rdv n'est qu'un booléen jamais lu").
--
-- LEFT JOIN sur notification_preference + COALESCE(..., true) : une ligne
-- n'existe que si le patient a ouvert l'écran préférences au moins une fois
-- (créée à la première PATCH, cf. auth/mod.rs) — le DEFAULT true de la
-- colonne (migration 0024) doit s'appliquer aussi en son absence.
--
-- Correction/extension d'une fonction déjà mergée sur main : convention
-- forward-only de ce dépôt (DROP+CREATE plutôt qu'éditer 0156).
-- Issue : #4036

DROP FUNCTION IF EXISTS due_reminders_for_dispatch();

CREATE FUNCTION due_reminders_for_dispatch()
  RETURNS TABLE(
    reminder_id       uuid,
    cabinet_id        uuid,
    appointment_id    uuid,
    kind              text,
    channel           text,
    app_user_id       uuid,
    has_active_device boolean,
    phone             text,
    sms_opted_in      boolean
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT
    r.id,
    r.cabinet_id,
    r.appointment_id,
    r.kind,
    r.channel,
    pa.app_user_id,
    COALESCE(
      EXISTS (
        SELECT 1 FROM device d
        WHERE d.app_user_id = pa.app_user_id
          AND d.active = true
          AND d.deleted_at IS NULL
      ),
      false
    ) AS has_active_device,
    pa.phone,
    COALESCE(np.sms_rdv, true) AS sms_opted_in
  FROM reminder r
  JOIN patient p ON p.id = r.patient_id
  LEFT JOIN patient_account pa ON pa.id = p.patient_account_id
  LEFT JOIN notification_preference np ON np.patient_account_id = pa.id
  WHERE r.status = 'pending' AND r.scheduled_at <= now();
$$;

ALTER FUNCTION due_reminders_for_dispatch() OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION due_reminders_for_dispatch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION due_reminders_for_dispatch() TO nubia_app;
