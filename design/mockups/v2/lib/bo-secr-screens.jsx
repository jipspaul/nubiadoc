// Nubia back-office — Secrétariat screens: Agenda, Fiche patient (admin),
// Suivi devis & paiements, Liste d'attente. AgendaDay is reused by the praticien.

// ── Shared agenda day grid ──
const AGENDA = {
  'Dr Lefèvre': [
    { s: 8.5, e: 9, name: 'Camille Rousseau', motif: 'Contrôle annuel', status: 'done' },
    { s: 9, e: 10, name: 'Marc Dubois', motif: 'Pose implant', status: 'in_progress' },
    { s: 10, e: 10.5, name: 'Inès Bachiri', motif: 'Détartrage', status: 'checked_in' },
    { s: 11.5, e: 12, name: '', motif: '', status: 'free' },
    { s: 14, e: 15, name: 'Léa Fontaine', motif: 'Consultation douleur', status: 'confirmed' },
    { s: 15, e: 16.5, name: 'Paul Girard', motif: 'Couronne céramique', status: 'confirmed' },
  ],
  'Dr Marin': [
    { s: 8.5, e: 11, name: 'Julien Mercier', motif: 'Chirurgie · greffe', status: 'confirmed' },
    { s: 11, e: 11.5, name: 'Sofia Lopez', motif: 'Suivi post-op', status: 'requested' },
    { s: 14, e: 14.5, name: 'Karim Saïdi', motif: 'Urgence · fracture', status: 'late' },
    { s: 14.5, e: 16, name: 'Nadia Klein', motif: 'Bilan implantaire', status: 'confirmed' },
  ],
};

function AgendaDay({ prats = ['Dr Lefèvre', 'Dr Marin'], dark }) {
  const start = 8, end = 18, hourH = 60;
  const hours = [];
  for (let h = start; h <= end; h++) hours.push(h);
  const tones = {
    done: { bg: 'var(--n-100)', bd: 'var(--border-default)', fg: 'var(--text-tertiary)' },
    in_progress: { bg: 'var(--primary)', bd: 'var(--primary)', fg: 'var(--text-on-primary)' },
    checked_in: { bg: 'var(--info-bg)', bd: 'var(--info-fg)', fg: 'var(--info-fg)' },
    confirmed: { bg: 'var(--primary-subtle-bg)', bd: 'var(--primary)', fg: 'var(--primary-subtle-fg)' },
    requested: { bg: 'var(--warning-bg)', bd: 'var(--warning-fg)', fg: 'var(--warning-fg)' },
    late: { bg: 'var(--danger-bg)', bd: 'var(--danger-fg)', fg: 'var(--danger-fg)' },
  };
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `52px repeat(${prats.length}, 1fr)`, background: 'var(--bg-surface)' }}>
      {/* header */}
      <div style={{ borderBottom: '1px solid var(--border-subtle)', borderRight: '1px solid var(--border-subtle)', height: 46 }} />
      {prats.map((p, i) => (
        <div key={i} style={{ height: 46, borderBottom: '1px solid var(--border-subtle)', borderRight: i < prats.length - 1 ? '1px solid var(--border-subtle)' : 'none',
          display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px' }}>
          <Avatar initials={p.split(' ')[1].slice(0, 1) + (p.split(' ')[1].slice(1, 2) || '')} size={26} tone="brand" />
          <span style={{ font: '600 13px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{p}</span>
        </div>
      ))}
      {/* time axis */}
      <div style={{ position: 'relative', borderRight: '1px solid var(--border-subtle)' }}>
        {hours.map((h, i) => (
          <div key={h} style={{ height: hourH, position: 'relative' }}>
            <span style={{ position: 'absolute', top: -7, right: 8, font: '500 11px/1 var(--font-ui)', color: 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{h}:00</span>
          </div>
        ))}
      </div>
      {/* columns */}
      {prats.map((p, ci) => (
        <div key={ci} style={{ position: 'relative', borderRight: ci < prats.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
          {hours.map((h, i) => <div key={h} style={{ height: hourH, borderBottom: '1px solid var(--border-subtle)' }} />)}
          {(AGENDA[p] || []).map((ev, i) => {
            const top = (ev.s - start) * hourH, height = (ev.e - ev.s) * hourH;
            if (ev.status === 'free') {
              return (
                <div key={i} style={{ position: 'absolute', top: top + 2, left: 6, right: 6, height: height - 4, borderRadius: 6,
                  border: '1.5px dashed var(--border-strong)', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                  color: 'var(--text-tertiary)', cursor: 'pointer' }}>
                  <Icon name="plus" size={14} stroke={2.4} /><span style={{ font: '500 11px/1 var(--font-ui)' }}>Libre</span>
                </div>
              );
            }
            const t = tones[ev.status] || tones.confirmed;
            return (
              <div key={i} style={{ position: 'absolute', top: top + 2, left: 6, right: 6, height: height - 4, borderRadius: 6,
                background: t.bg, borderLeft: `3px solid ${t.bd}`, padding: '6px 9px', overflow: 'hidden', cursor: 'pointer' }}>
                <div style={{ font: '600 12px/1.2 var(--font-ui)', color: t.fg, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.name}</div>
                {height > 36 && <div style={{ font: '400 11px/1.3 var(--font-ui)', color: t.fg, opacity: 0.85, marginTop: 1 }}>{ev.motif}</div>}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

function AgendaToolbar({ dark, chrome }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 18 }}>
      <Button size="sm" variant="secondary" icon="chevronL" style={{ padding: '0 10px' }}> </Button>
      <span style={{ font: '600 16px/1 var(--font-ui)', color: 'var(--text-primary)' }}>Mardi 3 juin 2025</span>
      <Button size="sm" variant="secondary" icon="chevronR" style={{ padding: '0 10px' }}> </Button>
      <span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--primary)', marginLeft: 6 }}>Aujourd'hui</span>
      <div style={{ flex: 1 }} />
      <div style={{ display: 'flex', gap: 4, padding: 4, background: 'var(--bg-page)', borderRadius: 'var(--r-md)', border: '1px solid var(--border-subtle)' }}>
        {['Jour', 'Semaine', 'Mois'].map((o, i) => (
          <span key={i} style={{ padding: '7px 16px', borderRadius: 'var(--r-sm)', font: `${i === 0 ? 600 : 500} 13px/1 var(--font-ui)`,
            background: i === 0 ? 'var(--bg-surface)' : 'transparent', color: i === 0 ? 'var(--text-primary)' : 'var(--text-tertiary)',
            boxShadow: i === 0 ? 'var(--shadow-sm)' : 'none', cursor: 'pointer' }}>{o}</span>
        ))}
      </div>
      <Button size="sm" variant="primary" icon="calendarPlus">Nouveau RDV</Button>
    </div>
  );
}

function ScreenSecrAgenda({ dark, chrome }) {
  return (
    <BOShell chrome={chrome} role="secretariat" active="agenda" title="Agenda" sub="Cabinet Lyon · 2 praticiens" dark={dark}>
      <AgendaToolbar dark={dark} />
      <Panel><AgendaDay dark={dark} /></Panel>
    </BOShell>
  );
}

// ── Fiche patient — vue administrative (cloisonnement) ──
function FicheField({ label, value, icon }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      <span style={{ font: '500 12px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{label}</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 7, font: '500 14px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>
        {icon && <span style={{ color: 'var(--text-tertiary)' }}><Icon name={icon} size={15} stroke={2} /></span>}{value}
      </span>
    </div>
  );
}

function ScreenSecrFiche({ dark, chrome }) {
  const tabs = ['Administratif', 'Rendez-vous', 'Devis & paiements', 'Documents'];
  return (
    <BOShell chrome={chrome} role="secretariat" active="patients" title="Fiche patient" sub="Vue administrative" dark={dark}
      actions={<Badge tone="sand" icon="lock">Accès secrétariat</Badge>}>
      {/* identity header */}
      <Panel style={{ marginBottom: 20 }} pad={20}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <Avatar initials="CR" size={56} tone="brand" />
          <div style={{ flex: 1 }}>
            <div style={{ font: '600 20px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>Camille Rousseau</div>
            <div style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>34 ans · née le 12/03/1991 · Patiente depuis 2019</div>
          </div>
          <Button size="sm" variant="secondary" icon="phoneIn">Appeler</Button>
          <Button size="sm" variant="primary" icon="calendarPlus">Planifier</Button>
        </div>
        {/* tabs */}
        <div style={{ display: 'flex', gap: 24, marginTop: 20, borderBottom: '1px solid var(--border-subtle)', marginLeft: -20, marginRight: -20, padding: '0 20px' }}>
          {tabs.map((t, i) => (
            <span key={i} style={{ padding: '0 0 12px', font: `${i === 0 ? 600 : 500} 14px/1 var(--font-ui)`,
              color: i === 0 ? 'var(--primary)' : 'var(--text-tertiary)', borderBottom: `2px solid ${i === 0 ? 'var(--primary)' : 'transparent'}`,
              marginBottom: -1, cursor: 'pointer' }}>{t}</span>
          ))}
        </div>
      </Panel>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, alignItems: 'start' }}>
        <Panel title="Coordonnées" pad={20}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18 }}>
            <FicheField label="Téléphone" value="06 12 34 56 78" icon="phoneIn" />
            <FicheField label="E-mail" value="camille.r@email.fr" icon="message" />
            <FicheField label="Adresse" value="24 rue Garibaldi, Lyon 6e" icon="mapPin" />
            <FicheField label="Contact d'urgence" value="M. Rousseau · 06 98…" icon="users" />
          </div>
        </Panel>
        <Panel title="Couverture" pad={20}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18 }}>
            <FicheField label="N° Sécurité sociale" value="2 91 03 69…" icon="creditCard" />
            <FicheField label="Mutuelle" value="MGEN · tiers payant" icon="shield" />
            <FicheField label="Médecin traitant" value="Déclaré" icon="check" />
            <FicheField label="Carte Vitale" value="À jour · 02/2025" icon="check" />
          </div>
        </Panel>

        {/* CLOISONNEMENT — clinical locked */}
        <Panel style={{ gridColumn: '1 / -1' }} pad={0}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: 22, background: 'var(--bg-page)' }}>
            <span style={{ width: 46, height: 46, borderRadius: 'var(--r-md)', background: 'var(--n-200)', color: 'var(--text-secondary)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Icon name="lock" size={22} stroke={2} /></span>
            <div style={{ flex: 1 }}>
              <div style={{ font: '600 15px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>Dossier clinique masqué</div>
              <div style={{ font: '400 13px/1.4 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>
                Notes, diagnostics et plan de traitement sont réservés au praticien (secret médical).
              </div>
            </div>
            <Badge tone="neutral" icon="lock">Accès praticien</Badge>
          </div>
        </Panel>

        <Panel title="Solde & paiements" pad={20} style={{ gridColumn: '1 / -1' }}>
          <div style={{ display: 'flex', gap: 28, alignItems: 'center' }}>
            <div><div style={{ font: '600 24px/1 var(--font-ui)', color: 'var(--danger-fg)', fontVariantNumeric: 'tabular-nums' }}>465 €</div>
              <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 5 }}>Acompte en attente</div></div>
            <div style={{ width: 1, height: 40, background: 'var(--border-subtle)' }} />
            <div><div style={{ font: '600 24px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>1 550 €</div>
              <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 5 }}>Reste à charge total</div></div>
            <div style={{ flex: 1 }} />
            <Button size="sm" variant="secondary" icon="creditCard">Relancer l'acompte</Button>
          </div>
        </Panel>
      </div>
    </BOShell>
  );
}

// ── Suivi devis & paiements ──
const DEVIS = [
  { patient: 'Camille Rousseau', init: 'CR', titre: 'Plan de soins implantaire', montant: '2 060 €', date: '02/06', status: 'signed', pay: 'acompte' },
  { patient: 'Marc Dubois', init: 'MD', titre: 'Couronne céramique', montant: '750 €', date: '01/06', status: 'paid', pay: 'paid' },
  { patient: 'Léa Fontaine', init: 'LF', titre: 'Traitement ortho', montant: '3 200 €', date: '30/05', status: 'sent', pay: '—' },
  { patient: 'Paul Girard', init: 'PG', titre: 'Détartrage + bilan', montant: '110 €', date: '29/05', status: 'paid', pay: 'paid' },
  { patient: 'Nadia Klein', init: 'NK', titre: 'Bilan implantaire', montant: '4 800 €', date: '24/05', status: 'expired', pay: '—' },
];
const DEVIS_STATUS = {
  sent: { label: 'Envoyé', tone: 'info', icon: 'send' },
  signed: { label: 'Signé · acompte dû', tone: 'warning', icon: 'clock' },
  paid: { label: 'Payé', tone: 'success', icon: 'check' },
  expired: { label: 'Expiré', tone: 'danger', icon: 'x2' },
};

function ScreenSecrDevis({ dark, chrome }) {
  const cols = '1.5fr 1.4fr 100px 70px 170px 110px';
  return (
    <BOShell chrome={chrome} role="secretariat" active="devis" title="Devis & paiements" sub="Suivi des devis envoyés et des règlements" dark={dark}>
      <div style={{ display: 'flex', gap: 16, marginBottom: 20 }}>
        <Metric icon="send" value="9" label="Devis envoyés (30 j)" />
        <Metric icon="clock" value="6" label="En attente de signature" alert="warning" />
        <Metric icon="creditCard" value="2" label="Acomptes à relancer" alert="danger" />
        <Metric icon="euro" value="12 480 €" label="Encaissé ce mois" />
      </div>
      <Panel title="Tous les devis" action={
        <div style={{ display: 'flex', gap: 8 }}><Chip icon="filter">Statut</Chip><Chip>Ce mois</Chip></div>}>
        <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '11px 18px',
          font: '600 11px/1 var(--font-ui)', letterSpacing: 0.4, textTransform: 'uppercase', color: 'var(--text-tertiary)', borderBottom: '1px solid var(--border-subtle)' }}>
          <span>Patient</span><span>Devis</span><span>Montant</span><span>Date</span><span>Statut</span><span></span>
        </div>
        {DEVIS.map((d, i) => {
          const s = DEVIS_STATUS[d.status];
          return (
            <div key={i} style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '13px 18px', alignItems: 'center',
              borderBottom: i < DEVIS.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Avatar initials={d.init} size={32} tone="neutral" />
                <span style={{ font: '500 14px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{d.patient}</span>
              </span>
              <span style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-secondary)' }}>{d.titre}</span>
              <span style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>{d.montant}</span>
              <span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{d.date}</span>
              <span><Badge tone={s.tone} icon={s.icon}>{s.label}</Badge></span>
              <span>{(d.status === 'signed' || d.status === 'expired') ?
                <Button size="sm" variant="secondary">Relancer</Button> :
                <span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>—</span>}</span>
            </div>
          );
        })}
      </Panel>
    </BOShell>
  );
}

// ── Liste d'attente / combler un trou (mocké) ──
function ScreenSecrAttente({ dark, chrome }) {
  const candidates = [
    { name: 'Sofia Lopez', init: 'SL', motif: 'Suivi post-op', flex: 'Dispo en journée', match: 'Idéal', tone: 'success' },
    { name: 'Antoine Berger', init: 'AB', motif: 'Détartrage', flex: 'Lun–Mer matin', match: 'Compatible', tone: 'info' },
    { name: 'Yasmine Adda', init: 'YA', motif: 'Contrôle', flex: 'Flexible', match: 'Compatible', tone: 'info' },
  ];
  return (
    <BOShell chrome={chrome} role="secretariat" active="attente" title="Liste d'attente" sub="Combler les créneaux libérés rapidement" dark={dark}
      actions={<Badge tone="info" icon="info">Démo</Badge>}>
      <div style={{ display: 'grid', gridTemplateColumns: '320px 1fr', gap: 20, alignItems: 'start' }}>
        {/* the gap */}
        <Panel title="Créneau à combler">
          <div style={{ padding: 18 }}>
            <div style={{ padding: 16, borderRadius: 'var(--r-lg)', background: 'var(--warning-bg)', marginBottom: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'var(--warning-fg)', marginBottom: 8 }}>
                <Icon name="clock" size={18} stroke={2} /><span style={{ font: '600 14px/1 var(--font-ui)' }}>Annulation à l'instant</span>
              </div>
              <div style={{ font: '600 22px/1 var(--font-ui)', color: 'var(--text-primary)' }}>11:30 – 12:00</div>
              <div style={{ font: '400 13px/1.4 var(--font-ui)', color: 'var(--text-secondary)', marginTop: 6 }}>Dr Lefèvre · 30 min · aujourd'hui</div>
            </div>
            <div style={{ font: '400 13px/1.5 var(--font-ui)', color: 'var(--text-tertiary)' }}>
              3 patients de la liste d'attente correspondent à ce créneau. Proposez-leur en un clic — le premier à accepter le réserve.
            </div>
          </div>
        </Panel>
        {/* candidates */}
        <Panel title="Patients compatibles" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>Trié par pertinence</span>}>
          {candidates.map((c, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px',
              borderBottom: i < candidates.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
              <Avatar initials={c.init} size={40} tone="neutral" />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{c.name}</span>
                  <Badge tone={c.tone} icon="check">{c.match}</Badge>
                </div>
                <div style={{ font: '400 13px/1.4 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 3 }}>{c.motif} · {c.flex}</div>
              </div>
              <Button size="sm" variant="secondary" icon="phoneIn">Appeler</Button>
              <Button size="sm" variant="primary" icon="send">Proposer</Button>
            </div>
          ))}
        </Panel>
      </div>
    </BOShell>
  );
}

Object.assign(window, {
  AGENDA, AgendaDay, AgendaToolbar, ScreenSecrAgenda,
  FicheField, ScreenSecrFiche, DEVIS, DEVIS_STATUS, ScreenSecrDevis, ScreenSecrAttente,
});
