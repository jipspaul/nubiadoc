-- #4291 : FK RLS-bypass — 3 derniers groupes du lot initial (parents isolés,
-- une seule table enfant chacun) : conversation, secretariat, provider.
-- Même pattern que 0210-0215 : FK composite (child_col, cabinet_id)
-- REFERENCES parent(id, cabinet_id).

-- ---- conversation -> message.conversation_id ----
ALTER TABLE conversation
  ADD CONSTRAINT conversation_id_cabinet_uniq UNIQUE (id, cabinet_id);
ALTER TABLE message DROP CONSTRAINT message_conversation_id_fkey;
ALTER TABLE message
  ADD CONSTRAINT message_conversation_id_cabinet_fkey
  FOREIGN KEY (conversation_id, cabinet_id) REFERENCES conversation (id, cabinet_id);

-- ---- secretariat -> secretariat_membership.secretariat_id ----
ALTER TABLE secretariat
  ADD CONSTRAINT secretariat_id_cabinet_uniq UNIQUE (id, cabinet_id);
ALTER TABLE secretariat_membership DROP CONSTRAINT secretariat_membership_secretariat_id_fkey;
ALTER TABLE secretariat_membership
  ADD CONSTRAINT secretariat_membership_secretariat_id_cabinet_fkey
  FOREIGN KEY (secretariat_id, cabinet_id) REFERENCES secretariat (id, cabinet_id);

-- ---- provider -> provider_verification.provider_id ----
-- provider.cabinet_id est NOT NULL depuis 0019 (praticien toujours rattaché
-- à un cabinet).
ALTER TABLE provider
  ADD CONSTRAINT provider_id_cabinet_uniq UNIQUE (id, cabinet_id);
ALTER TABLE provider_verification DROP CONSTRAINT provider_verification_provider_id_fkey;
ALTER TABLE provider_verification
  ADD CONSTRAINT provider_verification_provider_id_cabinet_fkey
  FOREIGN KEY (provider_id, cabinet_id) REFERENCES provider (id, cabinet_id);
