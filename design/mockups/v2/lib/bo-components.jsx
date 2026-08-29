// Nubia back-office — shared desktop components (sidebar shell, topbar, metrics,
// tables, agenda, status pills). Reuses Icon/Badge/Avatar/Button/Card from components.jsx.

// extend the icon set with back-office glyphs
Object.assign(NB_ICONS, {
  dashboard:  'M4 4h7v7H4V4ZM13 4h7v7h-7V4ZM4 13h7v7H4v-7ZM13 13h7v7h-7v-7Z',
  maximize:   'M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 1 2-2v-3',
  restore:    'M9 9V4M9 9H4M15 9V4M15 9h5M9 15v5M9 15H4M15 15v5M15 15h5',
  users:      'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM2 20a7 7 0 0 1 14 0M16.5 4.3a3.5 3.5 0 0 1 0 6.9M22 20a7 7 0 0 0-4.5-6.5',
  logout:     'M14 4h4a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-4M10 16l-4-4 4-4M6 12h11',
  more:       'M5 12h.01M12 12h.01M19 12h.01',
  moreV:      'M12 5h.01M12 12h.01M12 19h.01',
  creditCard: 'M3 7h18a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1ZM2 11h20',
  clipboard:  'M9 4h6v3H9V4ZM9 5H6a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1h-3',
  trendUp:    'M3 17l6-6 4 4 8-8M15 7h6v6',
  grip:       'M9 5h.01M9 12h.01M9 19h.01M15 5h.01M15 12h.01M15 19h.01',
  phoneIn:    'M5 4h3l2 5-2 1a11 11 0 0 0 5 5l1-2 5 2v3a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2Z',
  calendarPlus:'M7 3v3M17 3v3M4 8h16M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1ZM12 12v5M9.5 14.5h5',
  stethoscope:'M6 4v5a4 4 0 0 0 8 0V4M6 4H4M14 4h2M10 17v-3M10 17a4 4 0 0 0 8 0v-1M18 13a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z',
  x2:         'M6 6l12 12M18 6 6 18',
});

// ── RDV status → pill mapping ──
const RDV_STATUS = {
  requested:  { label: 'Demandé', tone: 'warning', icon: 'clock' },
  confirmed:  { label: 'Confirmé', tone: 'success', icon: 'check' },
  checked_in: { label: 'Enregistré', tone: 'info', icon: 'qr' },
  in_progress:{ label: 'En soin', tone: 'brand', icon: 'stethoscope' },
  waiting:    { label: 'En salle', tone: 'info', icon: 'clock' },
  done:       { label: 'Terminé', tone: 'neutral', icon: 'check' },
  no_show:    { label: 'Absent', tone: 'danger', icon: 'x2' },
  late:       { label: 'En retard', tone: 'danger', icon: 'clock' },
};
function StatusPill({ status }) {
  const s = RDV_STATUS[status] || RDV_STATUS.confirmed;
  return <Badge tone={s.tone} icon={s.icon}>{s.label}</Badge>;
}

// ── Sidebar nav definitions ──
const BO_NAV = {
  secretariat: [
    { id: 'dash', icon: 'dashboard', label: 'Tableau de bord' },
    { id: 'agenda', icon: 'calendar', label: 'Agenda' },
    { id: 'patients', icon: 'users', label: 'Patients' },
    { id: 'devis', icon: 'creditCard', label: 'Devis & paiements' },
    { id: 'msg', icon: 'message', label: 'Messagerie', badge: 5 },
    { id: 'salle', icon: 'clock', label: "Salle d'attente" },
    { id: 'attente', icon: 'list', label: "Liste d'attente" },
  ],
  praticien: [
    { id: 'dash', icon: 'dashboard', label: 'Tableau de bord' },
    { id: 'agenda', icon: 'calendar', label: 'Agenda' },
    { id: 'salle', icon: 'clock', label: "Salle d'attente" },
    { id: 'soins', icon: 'stethoscope', label: 'Au fauteuil' },
    { id: 'patients', icon: 'users', label: 'Patients' },
    { id: 'devis', icon: 'document', label: 'Devis & plans' },
    { id: 'msg', icon: 'message', label: 'Messagerie', badge: 3 },
  ],
};

const ROLE_META = {
  secretariat: { name: 'Sonia Bertrand', role: 'Secrétariat', initials: 'SB', tone: 'sand' },
  praticien:   { name: 'Dr Hugo Marin', role: 'Praticien', initials: 'HM', tone: 'brand' },
};

function Sidebar({ role, active, dark }) {
  const nav = BO_NAV[role];
  const me = ROLE_META[role];
  return (
    <div style={{
      width: 248, flexShrink: 0, background: 'var(--bg-surface)', borderRight: '1px solid var(--border-subtle)',
      display: 'flex', flexDirection: 'column', height: '100%',
    }}>
      {/* brand */}
      <div style={{ padding: '20px 20px 18px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ width: 30, height: 30, borderRadius: 9, background: 'var(--primary)', color: 'var(--text-on-primary)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="plus" size={18} stroke={2.6} /></span>
        <span style={{ font: '600 18px/1 var(--font-ui)', color: 'var(--text-primary)', letterSpacing: -0.3 }}>Nubia</span>
        <span style={{ marginLeft: 'auto', font: '600 10px/1 var(--font-ui)', letterSpacing: 0.5, textTransform: 'uppercase',
          color: 'var(--text-tertiary)' }}>Pro</span>
      </div>
      <div style={{ height: 1, background: 'var(--border-subtle)', margin: '0 16px 12px' }} />
      {/* nav */}
      <div style={{ flex: 1, padding: '0 12px', display: 'flex', flexDirection: 'column', gap: 2, overflow: 'auto' }}>
        {nav.map(n => {
          const on = n.id === active;
          return (
            <div key={n.id} style={{
              display: 'flex', alignItems: 'center', gap: 12, height: 42, padding: '0 12px', borderRadius: 'var(--r-md)',
              background: on ? 'var(--primary-subtle-bg)' : 'transparent',
              color: on ? 'var(--primary-subtle-fg)' : 'var(--text-secondary)', cursor: 'pointer',
            }}>
              <Icon name={n.icon} size={20} stroke={on ? 2.2 : 1.9} />
              <span style={{ font: `${on ? 600 : 500} 14px/1 var(--font-ui)`, flex: 1 }}>{n.label}</span>
              {n.badge && <span style={{ minWidth: 20, height: 20, padding: '0 6px', borderRadius: 10,
                background: on ? 'var(--primary)' : 'var(--danger-bg)', color: on ? 'var(--text-on-primary)' : 'var(--danger-fg)',
                font: '600 11px/20px var(--font-ui)', textAlign: 'center' }}>{n.badge}</span>}
            </div>
          );
        })}
      </div>
      {/* user */}
      <div style={{ padding: 12, borderTop: '1px solid var(--border-subtle)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 8px', borderRadius: 'var(--r-md)' }}>
          <Avatar initials={me.initials} size={36} tone={me.tone} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ font: '600 13px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>{me.name}</div>
            <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>{me.role} · Cabinet Lyon</div>
          </div>
          <span style={{ color: 'var(--text-tertiary)' }}><Icon name="logout" size={18} stroke={2} /></span>
        </div>
      </div>
    </div>
  );
}

function Topbar({ title, sub, dark, actions }) {
  return (
    <div style={{
      height: 68, flexShrink: 0, borderBottom: '1px solid var(--border-subtle)', background: 'var(--bg-surface)',
      display: 'flex', alignItems: 'center', gap: 16, padding: '0 28px',
    }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ font: '600 20px/1.2 var(--font-ui)', color: 'var(--text-primary)', letterSpacing: -0.3 }}>{title}</div>
        {sub && <div style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>{sub}</div>}
      </div>
      {/* search */}
      <div style={{ width: 240, height: 40, borderRadius: 'var(--r-md)', background: 'var(--bg-page)', border: '1px solid var(--border-subtle)',
        display: 'flex', alignItems: 'center', gap: 9, padding: '0 12px', color: 'var(--text-tertiary)' }}>
        <Icon name="search" size={18} stroke={2} />
        <span style={{ font: '400 13px/1 var(--font-ui)' }}>Rechercher un patient…</span>
      </div>
      {actions}
      <div style={{ width: 40, height: 40, borderRadius: 'var(--r-md)', border: '1px solid var(--border-subtle)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-secondary)', position: 'relative' }}>
        <Icon name="bell" size={20} stroke={2} />
        <span style={{ position: 'absolute', top: 8, right: 9, width: 7, height: 7, borderRadius: '50%', background: 'var(--danger-fg)' }} />
      </div>
    </div>
  );
}

// Live indicator chip (SSE)
function LiveChip({ label = 'Temps réel' }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '4px 10px 4px 8px', borderRadius: 'var(--r-full)',
      background: 'var(--success-bg)', color: 'var(--success-fg)', font: '500 12px/1 var(--font-ui)' }}>
      <span style={{ position: 'relative', width: 8, height: 8 }}>
        <span style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: 'var(--success-fg)' }} />
      </span>
      {label}
    </span>
  );
}

// ── App shell ──
function BOShell({ role, active, title, sub, actions, dark, chrome, children }) {
  const win = chrome === 'window';
  return (
    <div className={'nubia' + (dark ? ' nubia-dark' : '')} style={{ height: '100%', display: 'flex', background: 'var(--bg-page)', color: 'var(--text-primary)' }}>
      {!win && <Sidebar role={role} active={active} dark={dark} />}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <Topbar title={title} sub={sub} dark={dark} actions={actions} />
        <div style={{ flex: 1, overflow: 'auto', padding: win ? 24 : 28 }}>{children}</div>
      </div>
    </div>
  );
}

// ── Original window controls (NOT macOS traffic lights) ──
function WinControls({ isMax, onToggle, onClose }) {
  const base = { width: 30, height: 30, borderRadius: 8, border: 'none', background: 'transparent', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-tertiary)' };
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 3 }} onMouseDown={(e) => e.stopPropagation()}>
      {onToggle && <button className="winctl" title={isMax ? 'Réduire en fenêtre' : 'Plein écran'} onClick={onToggle} style={base}><Icon name={isMax ? 'restore' : 'maximize'} size={16} stroke={2} /></button>}
      {onClose && <button className="winctl-x" title="Fermer" onClick={onClose} style={base}><Icon name="x" size={17} stroke={2.4} /></button>}
    </div>
  );
}

// ── Metric tile ──
function Metric({ icon, value, label, tone = 'neutral', delta, alert }) {
  const accent = alert ? `var(--${alert}-fg)` : 'var(--primary)';
  const accentBg = alert ? `var(--${alert}-bg)` : 'var(--primary-subtle-bg)';
  return (
    <div style={{ flex: 1, minWidth: 0, background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)',
      borderRadius: 'var(--r-lg)', padding: 18, boxShadow: 'var(--shadow-sm)' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
        <span style={{ width: 36, height: 36, borderRadius: 'var(--r-md)', background: accentBg, color: accent,
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={icon} size={20} stroke={2} /></span>
        {delta && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, font: '500 12px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>
          <Icon name="trendUp" size={14} stroke={2} />{delta}</span>}
      </div>
      <div style={{ font: '600 28px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>{value}</div>
      <div style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-secondary)', marginTop: 5 }}>{label}</div>
    </div>
  );
}

// ── Panel (titled card) ──
function Panel({ title, action, children, pad = 0, style = {} }) {
  return (
    <div style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--r-lg)',
      boxShadow: 'var(--shadow-sm)', overflow: 'hidden', ...style }}>
      {title && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '15px 18px', borderBottom: '1px solid var(--border-subtle)' }}>
          <span style={{ font: '600 15px/1 var(--font-ui)', color: 'var(--text-primary)', flex: 1 }}>{title}</span>
          {action}
        </div>
      )}
      <div style={{ padding: pad }}>{children}</div>
    </div>
  );
}

Object.assign(window, {
  RDV_STATUS, StatusPill, BO_NAV, ROLE_META, Sidebar, Topbar, LiveChip, BOShell, WinControls, Metric, Panel, Bubble,
});

// chat bubble (cabinet messagerie)
function Bubble({ me, children, time }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: me ? 'flex-end' : 'flex-start', marginBottom: 10 }}>
      <div style={{ maxWidth: '100%', padding: '10px 14px', borderRadius: 14,
        borderBottomRightRadius: me ? 4 : 14, borderBottomLeftRadius: me ? 14 : 4,
        background: me ? 'var(--primary)' : 'var(--bg-surface)',
        color: me ? 'var(--text-on-primary)' : 'var(--text-primary)',
        border: me ? 'none' : '1px solid var(--border-subtle)', font: '400 14px/1.5 var(--font-ui)' }}>{children}</div>
      <span style={{ font: '500 11px/1 var(--font-ui)', color: 'var(--text-tertiary)', margin: '4px 4px 0' }}>{time}</span>
    </div>
  );
}
