-- 0011_rls_policies.sql
-- ⭐ Row-Level Security : ENABLE + FORCE + policies fail-closed sur TOUTE table tenant.
-- Réf. : docs/05 §2, §9.3 ; db/README §3-§4 ; db/migrations/README §9, §33.
--
-- Modèle de policy (fail-closed) :
--   cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
--   le `true` (missing_ok) => GUC absent => NULL => AUCUNE ligne (ni lecture ni écriture).
--   nullif(...,'') => robuste si le GUC a été RESET à '' (sinon ''::uuid lèverait une
--   erreur au lieu de renvoyer 0 ligne) : '' est traité comme « pas de contexte ».
-- Une seule policy `tenant_isolation` FOR ALL (USING + WITH CHECK identiques) couvre
-- lecture ET écriture (tenant_write de la spec est replié dedans : mêmes bornes).
-- FORCE => s'applique aussi au propriétaire et au rôle seed (NOBYPASSRLS).

-- ---------------------------------------------------------------------------
-- Tables tenant standard (isolation par cabinet_id)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'cabinet_membership','practitioner','patient','medical_record','clinical_note',
    'dental_chart','document','appointment','checkin_event','waiting_list_entry',
    'quote','quote_item','signature','payment_schedule','payment','conversation',
    'message','consent_record','treatment_plan','treatment_phase','prescription',
    'prescription_item','assistant_query'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($f$
      CREATE POLICY tenant_isolation ON %I
        FOR ALL
        USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
        WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    $f$, t);
  END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- cabinet : le tenant racine s'isole par sa propre clé `id`.
-- ---------------------------------------------------------------------------
ALTER TABLE cabinet ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON cabinet
  FOR ALL
  USING (id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- ---------------------------------------------------------------------------
-- audit_log : tenant + append-only. La policy WITH CHECK empêche d'INSÉRER une
-- entrée pour un autre cabinet (l'app n'a que INSERT, cf. 0008).
-- ---------------------------------------------------------------------------
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit_log
  FOR ALL
  USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- ---------------------------------------------------------------------------
-- provider : entité PLATEFORME (annuaire public). A un cabinet_id (lien) mais
-- N'EST PAS isolé par cabinet :
--   - lecture publique des profils LISTÉS (is_listed = true) ;
--   - le cabinet propriétaire gère ses propres profils (listés ou non).
-- ---------------------------------------------------------------------------
ALTER TABLE provider ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider FORCE ROW LEVEL SECURITY;
CREATE POLICY provider_public_read ON provider
  FOR SELECT
  USING (is_listed = true);
CREATE POLICY provider_cabinet_manage ON provider
  FOR ALL
  USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- ---------------------------------------------------------------------------
-- Entités plateforme SANS cabinet_id : pas de RLS cabinet (visibilité gérée par
-- l'API/RBAC au MVP) — patient_account, account_guardianship, profession,
-- specialty, medical_act, establishment, availability_slot, review, app_user.
--   NOTE : la restriction « review visible si published » et « patient_account
--   visible par le titulaire/cabinet lié » est portée par l'API au MVP ; une
--   migration ultérieure pourra durcir ces visibilités en policy. Signalé à Xav.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Grants finaux (réassertion ; les droits par défaut de 0001 couvrent déjà les
-- tables créées ensuite). audit_log reste INSERT-only (posé en 0008).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO nubia_seed;
-- re-restreindre l'audit après le GRANT large ci-dessus :
REVOKE ALL ON audit_log FROM nubia_app, nubia_seed;
REVOKE ALL ON audit_log_2026_05, audit_log_2026_06, audit_log_2026_07, audit_log_default
  FROM nubia_app, nubia_seed;
GRANT INSERT ON audit_log TO nubia_app;
