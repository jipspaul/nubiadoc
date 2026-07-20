-- 0156_due_reminders_for_dispatch_fn.sql
-- Fonction support du worker de dispatch des rappels RDV (#4034).
--
-- `reminder` est une table TENANT (cabinet_id, RLS tenant_isolation), mais
-- le balayage des rappels dus est intrinsèquement CROSS-CABINET (un seul
-- worker, toutes les cabinets). Résoudre "ce patient a-t-il un device actif
-- pour recevoir le push ?" exige de traverser patient (RLS cabinet_id) puis
-- patient_account (RLS app.current_account_id, self-only) puis device (RLS
-- app.current_user_id, self-only) — trois RLS différentes qu'un contexte
-- système sans utilisateur/cabinet courant ne peut pas satisfaire une à une.
--
-- Cette fonction SECURITY DEFINER (owner nubia_owner, BYPASSRLS) fait cette
-- résolution côté SQL et ne renvoie QUE des identifiants + un booléen —
-- jamais patient_account directement (même garde que ensure_patient_for_cabinet,
-- migration 0123 : ne jamais exposer patient_account brut à un appelant non
-- plateforme). Le worker Rust reste responsable du set_config
-- app.current_cabinet_id avant toute écriture sur `reminder` (RLS normale).
-- Issue : #4034

CREATE FUNCTION due_reminders_for_dispatch()
  RETURNS TABLE(
    reminder_id       uuid,
    cabinet_id        uuid,
    appointment_id    uuid,
    kind              text,
    app_user_id       uuid,
    has_active_device boolean
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
    pa.app_user_id,
    COALESCE(
      EXISTS (
        SELECT 1 FROM device d
        WHERE d.app_user_id = pa.app_user_id
          AND d.active = true
          AND d.deleted_at IS NULL
      ),
      false
    ) AS has_active_device
  FROM reminder r
  JOIN patient p ON p.id = r.patient_id
  LEFT JOIN patient_account pa ON pa.id = p.patient_account_id
  WHERE r.status = 'pending' AND r.scheduled_at <= now();
$$;

ALTER FUNCTION due_reminders_for_dispatch() OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION due_reminders_for_dispatch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION due_reminders_for_dispatch() TO nubia_app;
