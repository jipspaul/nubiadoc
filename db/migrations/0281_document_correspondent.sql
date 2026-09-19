-- 0281_document_correspondent.sql
-- Lien courrier -> correspondant destinataire (#7194, DP-F8.b) : le moteur de
-- courriers (letters.rs, #7197) accepte désormais un `correspondent_id`
-- (`cabinet_correspondent`, migration 0280) au lieu du `501
-- correspondent_not_supported` d'origine. Nullable : la plupart des
-- courriers (convocation, relance, attestation) ne sont adressés à aucun
-- correspondant. Sert à compter les « courriers envoyés » dans
-- `GET /v1/cabinet/correspondents/:id/stats`.
--
-- FK COMPOSITE (correspondent_id, cabinet_id) plutôt qu'une FK simple sur
-- l'id seul : même doctrine que 0280/0190/0193/0212 — empêche un `document`
-- de référencer un correspondant d'un autre cabinet (l'UNIQUE (id,
-- cabinet_id) posée par 0280 rend cette FK possible).

ALTER TABLE document ADD COLUMN correspondent_id uuid;
ALTER TABLE document
    ADD CONSTRAINT document_correspondent_cabinet_fkey
    FOREIGN KEY (correspondent_id, cabinet_id)
    REFERENCES cabinet_correspondent (id, cabinet_id);

CREATE INDEX idx_document_correspondent
    ON document (correspondent_id) WHERE correspondent_id IS NOT NULL;
