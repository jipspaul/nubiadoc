// Nubia back-office — Secrétariat dashboard (hero) in 3 directions + shared data.

const SALLE = [
  { h: '09:00', name: 'Camille Rousseau', init: 'CR', prat: 'Dr Lefèvre', arr: '08:52', status: 'waiting' },
  { h: '09:15', name: 'Marc Dubois', init: 'MD', prat: 'Dr Marin', arr: '09:05', status: 'in_progress' },
  { h: '09:30', name: 'Léa Fontaine', init: 'LF', prat: 'Dr Lefèvre', arr: '—', status: 'late' },
  { h: '09:45', name: 'Paul Girard', init: 'PG', prat: 'Dr Marin', arr: '09:38', status: 'checked_in' },
  { h: '10:00', name: 'Inès Bachiri', init: 'IB', prat: 'Dr Lefèvre', arr: '—', status: 'confirmed' },
];

const TASKS = [
  { icon: 'calendar', tone: 'warning', text: '3 RDV à confirmer', meta: 'Demain · relance auto possible', cta: 'Confirmer' },
  { icon: 'creditCard', tone: 'danger', text: '2 acomptes en attente', meta: 'Devis signés non réglés', cta: 'Relancer' },
  { icon: 'list', tone: 'info', text: 'Trou de 11:30 à 12:00', meta: 'Dr Lefèvre · combler ?', cta: 'Proposer' },
];

const URGENT_MSGS = [
  { init: 'LF', name: 'Léa Fontaine', text: 'Douleur intense depuis cette nuit, puis-je passer ?', time: 'il y a 8 min', tone: 'sand' },
  { init: 'TN', name: 'Thomas N.', text: 'Saignement après extraction, est-ce normal ?', time: 'il y a 22 min', tone: 'neutral' },
];

function MetricRow({ compact }) {
  const items = [
    { icon: 'calendar', value: '24', label: 'RDV aujourd\u2019hui', delta: '+3' },
    { icon: 'clock', value: '3', label: 'En salle d\u2019attente', alert: 'info' },
    { icon: 'creditCard', value: '6', label: 'Devis en attente', alert: 'warning' },
    { icon: 'message', value: '2', label: 'Messages urgents', alert: 'danger' },
    { icon: 'euro', value: '1 240 €', label: 'Encaissé du jour' },
  ];
  return (
    <div style={{ display: 'flex', gap: 16 }}>
      {items.map((m, i) => <Metric key={i} {...m} />)}
    </div>
  );
}

// ── Salle d'attente as a table ──
function SalleTable() {
  const cols = '70px 1fr 150px 96px 150px';
  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '10px 18px',
        font: '600 11px/1 var(--font-ui)', letterSpacing: 0.4, textTransform: 'uppercase', color: 'var(--text-tertiary)',
        borderBottom: '1px solid var(--border-subtle)' }}>
        <span>Heure</span><span>Patient</span><span>Praticien</span><span>Arrivée</span><span>Statut</span>
      </div>
      {SALLE.map((r, i) => (
        <div key={i} style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '13px 18px', alignItems: 'center',
          borderBottom: i < SALLE.length - 1 ? '1px solid var(--border-subtle)' : 'none',
          background: r.status === 'late' ? 'var(--danger-bg)' : 'transparent' }}>
          <span style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>{r.h}</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Avatar initials={r.init} size={32} tone="neutral" />
            <span style={{ font: '500 14px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{r.name}</span>
          </span>
          <span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-secondary)' }}>{r.prat}</span>
          <span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{r.arr}</span>
          <span><StatusPill status={r.status} /></span>
        </div>
      ))}
    </div>
  );
}

function TaskList() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column' }}>
      {TASKS.map((t, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 18px',
          borderBottom: i < TASKS.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
          <span style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flexShrink: 0, background: `var(--${t.tone}-bg)`, color: `var(--${t.tone}-fg)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={t.icon} size={18} stroke={2} /></span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ font: '500 14px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>{t.text}</div>
            <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>{t.meta}</div>
          </div>
          <Button size="sm" variant="secondary">{t.cta}</Button>
        </div>
      ))}
    </div>
  );
}

function UrgentList() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column' }}>
      {URGENT_MSGS.map((m, i) => (
        <div key={i} style={{ display: 'flex', gap: 11, padding: '14px 18px',
          borderBottom: i < URGENT_MSGS.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
          <Avatar initials={m.init} size={36} tone={m.tone} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 2 }}>
              <span style={{ font: '600 13px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{m.name}</span>
              <Badge tone="danger" icon="alert">Urgent</Badge>
              <span style={{ marginLeft: 'auto', font: '400 11px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{m.time}</span>
            </div>
            <div style={{ font: '400 13px/1.4 var(--font-ui)', color: 'var(--text-secondary)' }}>{m.text}</div>
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Weekly production mini-chart (reusable depth block) ──
function WeekBars({ data, max = 1600, accentDays = [] }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 14, height: 132, padding: '6px 4px 0' }}>
      {data.map((x, i) => {
        const on = accentDays.includes(x.d) || x.v === Math.max(...data.map(d => d.v));
        return (
          <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
            <span style={{ font: '600 11px/1 var(--font-ui)', color: on ? 'var(--text-secondary)' : 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums', opacity: x.v ? 1 : 0 }}>
              {(x.v / 1000).toFixed(1)}k</span>
            <div style={{ width: '100%', height: 96, display: 'flex', alignItems: 'flex-end' }}>
              <div style={{ width: '100%', height: `${Math.max(3, (x.v / max) * 100)}%`, borderRadius: 6,
                background: on ? 'var(--primary)' : 'var(--primary-subtle-bg)' }} />
            </div>
            <span style={{ font: '500 11px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{x.d}</span>
          </div>
        );
      })}
    </div>
  );
}

// ── Upcoming RDV strip (next 3) — adds forward-looking depth ──
function NextUp() {
  const rows = [
    { h: '09:30', name: 'Léa Fontaine', prat: 'Dr Lefèvre', motif: 'Consultation douleur', init: 'LF' },
    { h: '09:45', name: 'Paul Girard', prat: 'Dr Marin', motif: 'Couronne céramique', init: 'PG' },
    { h: '10:00', name: 'Inès Bachiri', prat: 'Dr Lefèvre', motif: 'Détartrage', init: 'IB' },
  ];
  return (
    <div>
      {rows.map((r, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 18px',
          borderBottom: i < rows.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
          <span style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums', width: 44 }}>{r.h}</span>
          <Avatar initials={r.init} size={32} tone="neutral" />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ font: '600 13px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{r.name}</div>
            <div style={{ font: '400 12px/1.2 var(--font-ui)', color: 'var(--text-tertiary)' }}>{r.motif} · {r.prat}</div>
          </div>
          <Badge tone="success" icon="check">Confirmé</Badge>
        </div>
      ))}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════
// A — Classique (spec F): metrics + salle d'attente table + colonne actions
// ═════════════════════════════════════════════════════════════
function ScreenSecrDashA({ dark, chrome }) {
  const week = [{ d: 'Lun', v: 820 }, { d: 'Mar', v: 1240 }, { d: 'Mer', v: 980 }, { d: 'Jeu', v: 1510 }, { d: 'Ven', v: 1120 }, { d: 'Sam', v: 640 }, { d: 'Dim', v: 0 }];
  return (
    <BOShell chrome={chrome} role="secretariat" active="dash" title="Tableau de bord" sub="Mardi 3 juin · 09:12 · Cabinet Lyon" dark={dark}
      actions={<LiveChip />}>
      <MetricRow />
      <div style={{ display: 'grid', gridTemplateColumns: '1.7fr 1fr', gap: 20, marginTop: 20, alignItems: 'start' }}>
        <Panel title="Salle d'attente" action={<LiveChip label="SSE · live" />}>
          <SalleTable />
        </Panel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="À faire aujourd'hui"><TaskList /></Panel>
          <Panel title="Messages urgents" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--primary)' }}>Tout voir</span>}>
            <UrgentList />
          </Panel>
        </div>
      </div>
      {/* depth row : occupancy timeline + forward-looking + production */}
      <div style={{ marginTop: 20 }}>
        <Panel title="Flux du jour" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>2 praticiens · 78 % d'occupation</span>}>
          <DayTimeline />
        </Panel>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginTop: 20, alignItems: 'start' }}>
        <Panel title="Prochains rendez-vous" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--primary)' }}>Voir l'agenda</span>}>
          <NextUp />
        </Panel>
        <Panel title="Encaissements de la semaine" action={
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>
            6 310 € <Badge tone="success" icon="trendUp">+12 %</Badge></span>}>
          <div style={{ padding: '14px 18px 18px' }}><WeekBars data={week} accentDays={['Mar']} /></div>
        </Panel>
      </div>
    </BOShell>
  );
}

// ═════════════════════════════════════════════════════════════
// B — Centre de pilotage : flux du jour (timeline d'occupation) en tête
// ═════════════════════════════════════════════════════════════
function DayTimeline() {
  // occupancy blocks across the day, 2 praticiens
  const hours = ['08', '09', '10', '11', '12', '13', '14', '15', '16', '17', '18'];
  const rows = [
    { prat: 'Dr Lefèvre', init: 'CL', blocks: [{ s: 1, w: 2, t: 'in' }, { s: 3.5, w: 1.5, t: 'free' }, { s: 5, w: 2, t: 'lunch' }, { s: 7, w: 3, t: 'conf' }] },
    { prat: 'Dr Marin', init: 'HM', blocks: [{ s: 0.5, w: 2.5, t: 'conf' }, { s: 5, w: 2, t: 'lunch' }, { s: 7.5, w: 1, t: 'free' }, { s: 8.5, w: 1.5, t: 'in' }] },
  ];
  const fill = { in: 'var(--primary)', conf: 'var(--primary-subtle-bg)', free: 'repeating-linear-gradient(45deg,var(--bg-page) 0 6px,var(--border-subtle) 6px 8px)', lunch: 'var(--n-100)' };
  const txt = { in: 'var(--text-on-primary)', conf: 'var(--primary-subtle-fg)', free: 'var(--text-tertiary)', lunch: 'var(--text-tertiary)' };
  const labels = { in: 'En soin', conf: 'RDV', free: 'Libre', lunch: 'Pause' };
  return (
    <div style={{ padding: 18 }}>
      <div style={{ display: 'grid', gridTemplateColumns: '110px 1fr', gap: 12 }}>
        <span></span>
        <div style={{ display: 'flex', justifyContent: 'space-between', font: '500 11px/1 var(--font-ui)', color: 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>
          {hours.map(h => <span key={h}>{h}h</span>)}
        </div>
      </div>
      {rows.map((r, i) => (
        <div key={i} style={{ display: 'grid', gridTemplateColumns: '110px 1fr', gap: 12, alignItems: 'center', marginTop: 12 }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Avatar initials={r.init} size={28} tone="brand" />
            <span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{r.prat}</span>
          </span>
          <div style={{ position: 'relative', height: 34, background: 'var(--bg-page)', borderRadius: 'var(--r-sm)', border: '1px solid var(--border-subtle)' }}>
            {r.blocks.map((b, j) => (
              <div key={j} style={{ position: 'absolute', top: 3, bottom: 3, left: `${(b.s / 10) * 100}%`, width: `${(b.w / 10) * 100}%`,
                background: fill[b.t], color: txt[b.t], borderRadius: 4, display: 'flex', alignItems: 'center', justifyContent: 'center',
                font: '600 11px/1 var(--font-ui)', overflow: 'hidden' }}>{b.w >= 1.5 ? labels[b.t] : ''}</div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function ScreenSecrDashB({ dark, chrome }) {
  return (
    <BOShell chrome={chrome} role="secretariat" active="dash" title="Tableau de bord" sub="Mardi 3 juin · 09:12 · Cabinet Lyon" dark={dark}
      actions={<LiveChip />}>
      <MetricRow />
      <div style={{ marginTop: 20 }}>
        <Panel title="Flux du jour" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>2 praticiens · 78 % d'occupation</span>}>
          <DayTimeline />
        </Panel>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1.7fr 1fr', gap: 20, marginTop: 20, alignItems: 'start' }}>
        <Panel title="Salle d'attente" action={<LiveChip label="SSE · live" />}><SalleTable /></Panel>
        <Panel title="Messages urgents"><UrgentList /></Panel>
      </div>
    </BOShell>
  );
}

// ═════════════════════════════════════════════════════════════
// C — Triage : actions d'abord + salle d'attente en board (kanban)
// ═════════════════════════════════════════════════════════════
function QueueBoard() {
  const cols = [
    { key: 'confirmed', title: 'Attendus', items: SALLE.filter(s => s.status === 'confirmed' || s.status === 'late') },
    { key: 'checked_in', title: 'Enregistrés', items: SALLE.filter(s => s.status === 'checked_in' || s.status === 'waiting') },
    { key: 'in_progress', title: 'En soin', items: SALLE.filter(s => s.status === 'in_progress') },
  ];
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 14, padding: 18 }}>
      {cols.map(c => (
        <div key={c.key} style={{ background: 'var(--bg-page)', borderRadius: 'var(--r-md)', padding: 12, minHeight: 180 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
            <span style={{ font: '600 12px/1 var(--font-ui)', textTransform: 'uppercase', letterSpacing: 0.4, color: 'var(--text-tertiary)' }}>{c.title}</span>
            <span style={{ font: '600 11px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{c.items.length}</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {c.items.map((it, i) => (
              <div key={i} style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--r-md)', padding: 11,
                borderLeft: it.status === 'late' ? '3px solid var(--danger-fg)' : '1px solid var(--border-subtle)' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Avatar initials={it.init} size={28} tone="neutral" />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ font: '600 13px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{it.name}</div>
                    <div style={{ font: '400 11px/1.2 var(--font-ui)', color: 'var(--text-tertiary)' }}>{it.h} · {it.prat}</div>
                  </div>
                </div>
                {it.status === 'late' && <div style={{ marginTop: 8 }}><StatusPill status="late" /></div>}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function ScreenSecrDashC({ dark, chrome }) {
  const strip = [
    { icon: 'calendar', value: '24', label: 'RDV' },
    { icon: 'clock', value: '3', label: 'En salle' },
    { icon: 'creditCard', value: '6', label: 'Devis' },
    { icon: 'euro', value: '1 240 €', label: 'Encaissé' },
  ];
  return (
    <BOShell chrome={chrome} role="secretariat" active="dash" title="Tableau de bord" sub="Mardi 3 juin · 09:12 · Cabinet Lyon" dark={dark}
      actions={<LiveChip />}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: 20, alignItems: 'start' }}>
        {/* left: actions feed */}
        <div>
          <Panel title="Ce qui demande votre attention" action={<Badge tone="danger" icon="alert">6 actions</Badge>}>
            <div>
              {/* urgent message highlighted first */}
              <div style={{ display: 'flex', gap: 12, padding: '14px 18px', background: 'var(--danger-bg)', alignItems: 'center' }}>
                <Avatar initials="LF" size={38} tone="sand" />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)' }}>Léa Fontaine</span>
                    <Badge tone="danger" icon="alert">Message urgent</Badge>
                  </div>
                  <div style={{ font: '400 13px/1.4 var(--font-ui)', color: 'var(--text-secondary)', marginTop: 3 }}>Douleur intense depuis cette nuit, puis-je passer ?</div>
                </div>
                <Button size="sm" variant="primary">Répondre</Button>
              </div>
              <TaskList />
            </div>
          </Panel>
        </div>
        {/* right: metric strip + mini */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            {strip.map((m, i) => (
              <div key={i} style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--r-lg)', padding: 14 }}>
                <span style={{ color: 'var(--primary)' }}><Icon name={m.icon} size={18} stroke={2} /></span>
                <div style={{ font: '600 22px/1 var(--font-ui)', color: 'var(--text-primary)', marginTop: 8, fontVariantNumeric: 'tabular-nums' }}>{m.value}</div>
                <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 4 }}>{m.label}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={{ marginTop: 20 }}>
        <Panel title="Salle d'attente" action={<LiveChip label="SSE · live" />}><QueueBoard /></Panel>
      </div>
    </BOShell>
  );
}

Object.assign(window, {
  SALLE, TASKS, URGENT_MSGS, MetricRow, SalleTable, TaskList, UrgentList, WeekBars, NextUp,
  ScreenSecrDashA, DayTimeline, ScreenSecrDashB, QueueBoard, ScreenSecrDashC,
});
