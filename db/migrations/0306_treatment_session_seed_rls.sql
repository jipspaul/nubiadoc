-- 0306_treatment_session_seed_rls.sql
-- [db] #6956 : `treatment_session`/`treatment_session_act` (migration 0288)
-- n'ont qu'une policy `tenant_isolation` scopée `TO nubia_app` — sans policy
-- `TO nubia_seed`, contrairement au pattern établi pour toute table posée
-- après la boucle générique de 0011 (`device_seed`/0052, `nurse_seed_all`/
-- 0233, `visit_request_seed_all`/0234, `access_request_seed`/0241, …) : le
-- seed démo (rôle `nubia_seed`, NOBYPASSRLS) ne peut écrire aucune ligne,
-- RLS fail-closed sous FORCE ROW LEVEL SECURITY. Le GRANT nubia_seed posé
-- par 0288 existe déjà mais restait inopérant faute de policy applicable.
-- Bloquait le seed d'une séance reliant une phase de plan de soins à son
-- rendez-vous (CTA « Voir mon rendez-vous » côté patient).

CREATE POLICY treatment_session_seed ON treatment_session
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);

CREATE POLICY treatment_session_act_seed ON treatment_session_act
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);
