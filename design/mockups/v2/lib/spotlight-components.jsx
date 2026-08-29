// Nubia Spotlight — demo components rendered inside macOS-style windows.
// All in-memory data. Uses Icon/NB_ICONS from components.jsx and tokens.css vars.

// ── 1. Agenda du jour (calendar) ──
function CompAgenda() {
  const rows = [
    { h: '08:30', name: 'Camille Rousseau', motif: 'Contrôle annuel', tone: 'neutral', done: true },
    { h: '09:00', name: 'Marc Dubois', motif: 'Pose implant', tone: 'success', now: true },
    { h: '10:00', name: 'Inès Bachiri', motif: 'Détartrage', tone: 'info' },
    { h: '11:30', name: '— créneau libre —', motif: '', tone: 'free' },
    { h: '14:00', name: 'Léa Fontaine', motif: 'Consultation douleur', tone: 'warning' },
    { h: '15:00', name: 'Paul Girard', motif: 'Couronne céramique', tone: 'brand' },
  ];
  const dot = { neutral: 'var(--text-tertiary)', success: 'var(--primary)', info: 'var(--info-fg)', warning: 'var(--warning-fg)', brand: 'var(--primary)', free: 'transparent' };
  return (
    <div style={{ padding: 20, width: '100%' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 16 }}>
        <span style={{ fontSize: 17, fontWeight: 600, color: 'var(--text-primary)' }}>Mardi 3 juin</span>
        <span style={{ fontSize: 13, color: 'var(--text-tertiary)' }}>6 rendez-vous</span>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        {rows.map((r, i) => (
          <div key={i} style={{ display: 'flex', gap: 14, padding: '11px 0', alignItems: 'center',
            borderTop: i ? '1px solid var(--border-subtle)' : 'none', opacity: r.tone === 'free' ? 0.6 : 1 }}>
            <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-secondary)', width: 44, fontVariantNumeric: 'tabular-nums' }}>{r.h}</span>
            <span style={{ width: 8, height: 8, borderRadius: '50%', background: dot[r.tone], border: r.tone === 'free' ? '1.5px dashed var(--border-strong)' : 'none', flexShrink: 0 }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: r.tone === 'free' ? 400 : 600, color: r.tone === 'free' ? 'var(--text-tertiary)' : 'var(--text-primary)' }}>{r.name}</div>
              {r.motif && <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>{r.motif}</div>}
            </div>
            {r.now && <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--primary)', background: 'var(--primary-subtle-bg)', padding: '3px 8px', borderRadius: 999 }}>en cours</span>}
          </div>
        ))}
      </div>
    </div>
  );
}

// ── 2. Fiche patient (profile card) ──
function CompFiche() {
  const F = ({ label, value }) => (
    <div><div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>{label}</div>
      <div style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-primary)', marginTop: 3 }}>{value}</div></div>
  );
  return (
    <div style={{ width: '100%' }}>
      <div style={{ padding: '24px 20px', background: 'var(--primary-subtle-bg)', display: 'flex', alignItems: 'center', gap: 16 }}>
        <Avatar initials="CR" size={56} tone="brand" />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)' }}>Camille Rousseau</div>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 2 }}>34 ans · Patiente depuis 2019</div>
        </div>
        <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--primary-subtle-fg)', background: 'var(--bg-surface)', padding: '4px 10px', borderRadius: 999 }}>À jour</span>
      </div>
      <div style={{ padding: 20, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18 }}>
        <F label="Téléphone" value="06 12 34 56 78" />
        <F label="Mutuelle" value="MGEN · tiers payant" />
        <F label="Prochain RDV" value="3 juin · 08:30" />
        <F label="Reste à charge" value="1 550 €" />
      </div>
      <div style={{ padding: '0 20px 20px', display: 'flex', gap: 10 }}>
        <NBtn icon="phone">Appeler</NBtn>
        <NBtn icon="calendar" primary>Planifier</NBtn>
      </div>
    </div>
  );
}

// ── 3. Encaissements (chart) ──
function CompChart() {
  const data = [{ d: 'Lun', v: 820 }, { d: 'Mar', v: 1240 }, { d: 'Mer', v: 980 }, { d: 'Jeu', v: 1510 }, { d: 'Ven', v: 1120 }, { d: 'Sam', v: 640 }, { d: 'Dim', v: 0 }];
  const max = 1600, total = data.reduce((s, x) => s + x.v, 0);
  return (
    <div style={{ width: '100%', padding: 22 }}>
      <div style={{ fontSize: 13, color: 'var(--text-tertiary)' }}>Encaissé cette semaine</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 4 }}>
        <span style={{ fontSize: 30, fontWeight: 700, color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>{total.toLocaleString('fr-FR')} €</span>
        <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--primary)' }}>+12 %</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12, height: 140, marginTop: 22 }}>
        {data.map((x, i) => (
          <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
            <div style={{ width: '100%', height: 120, display: 'flex', alignItems: 'flex-end' }}>
              <div style={{ width: '100%', height: `${Math.max(2, (x.v / max) * 100)}%`, borderRadius: 6,
                background: x.v === max || x.v === 1510 ? 'var(--primary)' : 'var(--primary-subtle-bg)' }} />
            </div>
            <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>{x.d}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── 4. Note rapide (note) — editable, in-memory ──
function CompNote() {
  const [text, setText] = React.useState('Rappeler le labo pour la couronne de M. Girard.\nCommander gants nitrile (taille M).\nRelancer devis Mme Klein avant vendredi.');
  return (
    <div style={{ width: '100%', padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
        <span style={{ color: 'var(--accent-700)' }}><Icon name="edit" size={18} stroke={2} /></span>
        <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', flex: 1 }}>Note du cabinet</span>
        <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>en mémoire</span>
      </div>
      <textarea value={text} onChange={e => setText(e.target.value)} spellCheck={false} style={{
        width: '100%', minHeight: 180, resize: 'none', border: 'none', outline: 'none', background: 'transparent',
        font: '400 14px/1.7 inherit', color: 'var(--text-primary)',
      }} />
    </div>
  );
}

// ── 5. Calculatrice reste à charge (calculator) — ties to the wedge ──
function CompCalc() {
  const [total, setTotal] = React.useState(2060);
  const [pris, setPris] = React.useState(510);
  const [pct, setPct] = React.useState(30);
  const reste = Math.max(0, total - pris);
  const acompte = Math.round((reste * pct) / 100);
  const Field = ({ label, value, set }) => (
    <label style={{ flex: 1, display: 'block' }}>
      <span style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>{label}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 5, padding: '9px 12px', borderRadius: 8,
        background: 'var(--bg-page)', border: '1px solid var(--border-default)' }}>
        <input type="number" value={value} onChange={e => set(+e.target.value || 0)} style={{
          width: '100%', border: 'none', outline: 'none', background: 'transparent', font: '600 15px/1 inherit', color: 'var(--text-primary)' }} />
        <span style={{ fontSize: 14, color: 'var(--text-tertiary)' }}>€</span>
      </div>
    </label>
  );
  return (
    <div style={{ width: '100%', padding: 20 }}>
      <div style={{ display: 'flex', gap: 12, marginBottom: 14 }}>
        <Field label="Total des soins" value={total} set={setTotal} />
        <Field label="Pris en charge" value={pris} set={setPris} />
      </div>
      <div style={{ marginBottom: 16 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'var(--text-tertiary)', marginBottom: 6 }}>
          <span>Acompte demandé</span><span style={{ fontWeight: 600, color: 'var(--text-secondary)' }}>{pct} %</span>
        </div>
        <input type="range" min="0" max="100" step="5" value={pct} onChange={e => setPct(+e.target.value)}
          style={{ width: '100%', accentColor: 'var(--primary)' }} />
      </div>
      <div style={{ padding: 16, borderRadius: 12, background: 'var(--primary)', color: 'var(--text-on-primary)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: 13, opacity: 0.85 }}>Reste à charge</span>
          <span style={{ fontSize: 24, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{reste.toLocaleString('fr-FR')} €</span>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 8, paddingTop: 8, borderTop: '1px solid rgba(255,255,255,0.2)' }}>
          <span style={{ fontSize: 13, opacity: 0.85 }}>Acompte aujourd'hui</span>
          <span style={{ fontSize: 18, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{acompte.toLocaleString('fr-FR')} €</span>
        </div>
      </div>
    </div>
  );
}

// ── 6. Salle d'attente (live list) ──
function CompSalle() {
  const rows = [
    { name: 'Marc Dubois', init: 'MD', s: 'En soin', tone: 'success', meta: 'Salle 2 · Dr Lefèvre' },
    { name: 'Paul Girard', init: 'PG', s: 'Enregistré', tone: 'info', meta: 'arrivé à 09:38' },
    { name: 'Léa Fontaine', init: 'LF', s: 'En retard', tone: 'danger', meta: 'attendu à 09:30' },
    { name: 'Inès Bachiri', init: 'IB', s: 'Attendue', tone: 'neutral', meta: '10:00' },
  ];
  const c = { success: 'var(--primary)', info: 'var(--info-fg)', danger: 'var(--danger-fg)', neutral: 'var(--text-tertiary)' };
  return (
    <div style={{ width: '100%', padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14 }}>
        <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--primary)' }} />
        <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--primary)', textTransform: 'uppercase', letterSpacing: 0.4, flex: 1 }}>Temps réel</span>
        <span style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>4 patients</span>
      </div>
      {rows.map((r, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderTop: i ? '1px solid var(--border-subtle)' : 'none' }}>
          <Avatar initials={r.init} size={36} tone="neutral" />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-primary)' }}>{r.name}</div>
            <div style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>{r.meta}</div>
          </div>
          <span style={{ fontSize: 12, fontWeight: 600, color: c[r.tone] }}>{r.s}</span>
        </div>
      ))}
    </div>
  );
}

// small button used in components
function NBtn({ children, icon, primary, onClick }) {
  return (
    <button onClick={onClick} style={{
      flex: 1, height: 38, borderRadius: 9, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7,
      font: '600 13px/1 inherit', border: primary ? 'none' : '1px solid var(--border-default)',
      background: primary ? 'var(--primary)' : 'var(--bg-surface)', color: primary ? 'var(--text-on-primary)' : 'var(--text-primary)',
    }}>{icon && <Icon name={icon} size={16} stroke={2} />}{children}</button>
  );
}

window.NUBIA_COMPONENTS = {
  agenda: CompAgenda, fiche: CompFiche, chart: CompChart, note: CompNote, calc: CompCalc, salle: CompSalle,
};
Object.assign(window, { CompAgenda, CompFiche, CompChart, CompNote, CompCalc, CompSalle, NBtn });
