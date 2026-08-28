// Nubia Spotlight — STATIC presentational pieces for the comparison canvas.
// Spotlight windows now render the REAL back-office screens (chrome="window" =
// same content as V1 minus the sidebar). Self-contained glass styling.

Object.assign(NB_ICONS, {
  maximize: 'M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 1 2-2v-3',
  restore: 'M9 9V4M9 9H4M15 9V4M15 9h5M9 15v5M9 15H4M15 15v5M15 15h5',
});

// view registry → real screens (globals, loaded before this file)
const VIEW = {
  dash:   { icon: 'dashboard',  title: 'Tableau de bord',   screen: 'ScreenSecrDashA',      desc: 'Activité du jour' },
  agenda: { icon: 'calendar',   title: 'Agenda',            screen: 'ScreenSecrAgenda',     desc: 'Planning du cabinet' },
  salle:  { icon: 'clock',      title: "Salle d'attente",   screen: 'ScreenPratSalle',      desc: 'File en temps réel' },
  devis:  { icon: 'creditCard', title: 'Devis & paiements', screen: 'ScreenSecrDevis',      desc: 'Suivi & relances' },
  fiche:  { icon: 'user',       title: 'Fiche patient',     screen: 'ScreenPratFiche',      desc: 'Dossier patient' },
  msg:    { icon: 'message',    title: 'Messagerie',        screen: 'ScreenPratMessagerie', desc: 'File priorisée' },
  // praticien — le cœur de l'app
  pratdash: { icon: 'dashboard', title: 'Tableau de bord praticien', screen: 'ScreenPratDashboard',    desc: 'Ma journée clinique' },
  patients: { icon: 'users',     title: 'Mes patients',              screen: 'ScreenPratPatients',     desc: 'Dossiers suivis' },
  consult:  { icon: 'stethoscope', title: 'Consultation au fauteuil', screen: 'ScreenPratConsultation', desc: 'Soin en cours' },
  plan:     { icon: 'document',  title: 'Plan de traitement',        screen: 'ScreenPratPlan',         desc: 'Devis & phases' },
  ordo:     { icon: 'pill',      title: 'Ordonnance',                screen: 'ScreenPratOrdonnance',   desc: 'Prescription sécurisée' },
  assistant: { icon: 'message', title: 'Nubia',             screen: null,                   desc: 'Réponse en langage naturel' },
};

const wallBg = (dark) => dark
  ? 'radial-gradient(55% 45% at 16% 10%, rgba(16,185,129,0.22), transparent 70%), radial-gradient(48% 48% at 88% 16%, rgba(176,137,79,0.18), transparent 70%), radial-gradient(60% 55% at 72% 98%, rgba(16,185,129,0.16), transparent 70%), linear-gradient(160deg, #1A1613, #0E0C0A)'
  : 'radial-gradient(55% 45% at 16% 10%, rgba(5,150,105,0.16), transparent 70%), radial-gradient(48% 48% at 88% 16%, rgba(176,137,79,0.14), transparent 70%), radial-gradient(60% 55% at 72% 98%, rgba(5,150,105,0.12), transparent 70%), linear-gradient(160deg, #F7F6F3, #ECEAE5)';
const glassBar = (dark) => ({
  backdropFilter: 'blur(34px) saturate(180%)', WebkitBackdropFilter: 'blur(34px) saturate(180%)',
  background: dark ? 'rgba(38,35,33,0.74)' : 'rgba(255,255,255,0.80)',
  border: dark ? '1px solid rgba(255,255,255,0.10)' : '1px solid rgba(255,255,255,0.7)',
  boxShadow: dark ? '0 24px 80px rgba(0,0,0,0.55)' : '0 24px 70px rgba(28,25,23,0.22), 0 2px 8px rgba(28,25,23,0.08)',
});
const glassDock = (dark) => ({
  backdropFilter: 'blur(34px) saturate(180%)', WebkitBackdropFilter: 'blur(34px) saturate(180%)',
  background: dark ? 'rgba(40,37,35,0.5)' : 'rgba(255,255,255,0.55)',
  border: dark ? '1px solid rgba(255,255,255,0.1)' : '1px solid rgba(255,255,255,0.6)',
  boxShadow: dark ? '0 12px 50px rgba(0,0,0,0.5)' : '0 12px 40px rgba(28,25,23,0.18)',
});
const winShadow = (dark) => dark ? '0 40px 120px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.08)' : '0 40px 120px rgba(28,25,23,0.4), 0 0 0 1px rgba(0,0,0,0.06)';

// search bar — "ask Nubia" first (the product's power), then views
function SpotBarStatic({ dark, query = '', sel = 0 }) {
  const ask = { ask: true, icon: 'message', title: 'Demander à Nubia', desc: query ? `« ${query} »` : 'Posez une question — résumé, relances, chiffres du jour' };
  const views = ['dash', 'agenda', 'salle', 'devis', 'fiche'].map(id => ({ id, icon: VIEW[id].icon, title: VIEW[id].title, desc: VIEW[id].desc }));
  const rows = [ask, ...views];
  const chips = ['Résume ma journée', 'Quels devis relancer ?', 'Combien encaissé aujourd\u2019hui ?'];
  return (
    <div style={{ ...glassBar(dark), width: 620, borderRadius: 18, overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '17px 20px' }}>
        <span style={{ color: 'var(--text-tertiary)' }}><Icon name="search" size={23} stroke={2} /></span>
        <span style={{ flex: 1, font: '400 21px/1.2 inherit', color: query ? 'var(--text-primary)' : 'var(--text-tertiary)' }}>
          {query || 'Posez votre question, ou cherchez une vue…'}</span>
        <kbd style={{ font: '600 11px/1 inherit', color: 'var(--text-tertiary)', border: '1px solid var(--border-default)', borderRadius: 6, padding: '4px 7px' }}>esc</kbd>
      </div>
      <div style={{ borderTop: '1px solid var(--border-subtle)', padding: 8 }}>
        {rows.map((r, i) => (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '11px 12px', borderRadius: 11, background: i === sel ? 'var(--primary-subtle-bg)' : 'transparent' }}>
            <span style={{ width: 38, height: 38, borderRadius: 9, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
              background: r.ask ? 'var(--primary)' : (i === sel ? 'var(--bg-surface)' : 'var(--bg-page)'), color: r.ask ? 'var(--text-on-primary)' : 'var(--primary)' }}>
              <Icon name={r.icon} size={20} stroke={2} /></span>
            <div style={{ flex: 1 }}>
              <div style={{ font: '600 15px/1.3 inherit', color: 'var(--text-primary)' }}>{r.title}{r.ask && <span style={{ marginLeft: 8, font: '600 10px/1 inherit', letterSpacing: 0.5, textTransform: 'uppercase', color: 'var(--primary)', background: 'var(--primary-subtle-bg)', padding: '3px 7px', borderRadius: 999 }}>IA</span>}</div>
              <div style={{ font: '400 13px/1.3 inherit', color: 'var(--text-tertiary)' }}>{r.desc}</div>
            </div>
            {i === sel && <kbd style={{ font: '600 11px/1 inherit', color: 'var(--text-tertiary)' }}>↵</kbd>}
          </div>
        ))}
        {!query && (
          <div style={{ display: 'flex', gap: 7, padding: '8px 12px 6px', flexWrap: 'wrap' }}>
            {chips.map((c, i) => (
              <span key={i} style={{ font: '500 12px/1 inherit', color: 'var(--text-secondary)', background: 'var(--bg-page)', border: '1px solid var(--border-subtle)', padding: '7px 11px', borderRadius: 999 }}>{c}</span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// window chrome — original controls (no macOS traffic lights). full | small.
function WinStatic({ dark, icon, title, full, small, children }) {
  const Ws = 600, head = 42, contentH = 352, scale = Ws / 1180;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', overflow: 'hidden', background: 'var(--bg-surface)', boxShadow: winShadow(dark),
      height: full ? '100%' : (small ? head + contentH : 'auto'), width: full ? '100%' : (small ? Ws : 'auto'), borderRadius: full ? 16 : 13 }}>
      <div style={{ height: head, flexShrink: 0, display: 'flex', alignItems: 'center', gap: 9, padding: '0 8px 0 14px', borderBottom: '1px solid var(--border-subtle)' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, font: '600 13px/1 inherit', color: 'var(--text-primary)' }}>
          <span style={{ color: 'var(--primary)' }}><Icon name={icon} size={15} stroke={2} /></span>{title}</span>
        <span style={{ flex: 1 }} />
        <WinControls isMax={full} onToggle={() => {}} onClose={() => {}} />
      </div>
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
        {small
          ? <div style={{ width: Ws, height: contentH, overflow: 'hidden' }}><div style={{ width: 1180, height: contentH / scale, transform: `scale(${scale})`, transformOrigin: 'top left' }}>{children}</div></div>
          : <div style={{ height: '100%' }}>{children}</div>}
      </div>
    </div>
  );
}

function SpotWindow({ dark, viewId, full, small }) {
  const v = VIEW[viewId] || VIEW.assistant;
  const inner = viewId === 'assistant' ? <AssistantStatic /> : (() => { const S = window[v.screen]; return S ? <S dark={dark} chrome="window" /> : null; })();
  return <WinStatic dark={dark} icon={v.icon} title={v.title} full={full} small={small}>{inner}</WinStatic>;
}

function DockStatic({ dark, dockIds = [], activeId }) {
  const empty = dockIds.length === 0;
  const tiles = [{ id: '__search', icon: 'search', search: true }, ...dockIds.map(id => ({ id, icon: (VIEW[id] || VIEW.assistant).icon }))];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9 }}>
      {empty && (
        <div style={{ font: '500 12px/1 inherit', color: 'var(--text-secondary)', background: 'var(--bg-surface)',
          border: '1px solid var(--border-subtle)', padding: '6px 13px', borderRadius: 999, boxShadow: 'var(--shadow-sm)' }}>
          Le dock est vide — il se remplit des vues que vous ouvrez
        </div>
      )}
      <div style={{ ...glassDock(dark), display: 'flex', alignItems: 'flex-end', gap: 10, padding: '10px 12px', borderRadius: 20 }}>
        {tiles.map((t) => {
          const active = !t.search && t.id === activeId;
          return (
            <div key={t.id} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <div style={{ width: 52, height: 52, borderRadius: 13, display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: t.search ? 'linear-gradient(160deg, var(--primary), var(--brand-800))' : 'var(--bg-surface)',
                color: t.search ? 'var(--text-on-primary)' : 'var(--primary)',
                border: t.search ? 'none' : '1px solid var(--border-subtle)', boxShadow: 'var(--shadow-md)' }}>
                <Icon name={t.icon} size={24} stroke={2} />
              </div>
              <span style={{ width: 4, height: 4, borderRadius: '50%', marginTop: 5, background: active ? 'var(--primary)' : 'transparent' }} />
            </div>
          );
        })}
      </div>
    </div>
  );
}

// static desktop composition. mode: search | full | windows
function SpotStatic({ dark, mode = 'full', view = 'dash', second = 'agenda', dockIds, query, sel }) {
  const dids = dockIds || (mode === 'search' ? [] : (mode === 'windows' ? [view, second] : [view]));
  return (
    <div className={'nubia' + (dark ? ' nubia-dark' : '')} style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden',
      fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif', color: 'var(--text-primary)' }}>
      <div style={{ position: 'absolute', inset: 0, background: wallBg(dark) }} />

      {mode === 'search' && (
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(20,16,12,0.28)', display: 'flex', alignItems: 'flex-start', justifyContent: 'center', paddingTop: '11%' }}>
          <SpotBarStatic dark={dark} query={query} sel={sel} />
        </div>
      )}
      {mode === 'full' && (
        <div style={{ position: 'absolute', top: 14, left: 14, right: 14, bottom: 92 }}>
          <SpotWindow dark={dark} viewId={view} full />
        </div>
      )}
      {mode === 'windows' && (
        <React.Fragment>
          <div style={{ position: 'absolute', left: 54, top: 70 }}><SpotWindow dark={dark} viewId={second} small /></div>
          <div style={{ position: 'absolute', left: 410, top: 196 }}><SpotWindow dark={dark} viewId={view} small /></div>
        </React.Fragment>
      )}

      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 16, display: 'flex', justifyContent: 'center' }}>
        <DockStatic dark={dark} dockIds={dids} activeId={mode === 'windows' ? view : (mode === 'search' ? null : view)} />
      </div>
    </div>
  );
}

// static assistant transcript
function AssistantStatic() {
  const answer = "Voici votre journée :\n\n• 24 rendez-vous prévus aujourd'hui\n• 1 240 € encaissés\n• 6 devis en attente de validation\n• 2 acomptes à relancer :\n   – Camille Rousseau (465 €)\n   – Nadia Klein\n\nActions suggérées : envoyer les relances d'acompte et confirmer les 3 RDV de demain.";
  return (
    <div style={{ width: '100%', height: '100%', minHeight: 360, display: 'flex', flexDirection: 'column' }}>
      <div style={{ flex: 1, overflow: 'hidden', padding: 24 }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
          <div style={{ padding: '10px 14px', borderRadius: 14, borderBottomRightRadius: 4, background: 'var(--primary)', color: 'var(--text-on-primary)', font: '400 14px/1.5 inherit' }}>Résume ma journée</div>
        </div>
        <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
          <div style={{ maxWidth: 520, padding: '12px 16px', borderRadius: 14, borderBottomLeftRadius: 4, background: 'var(--bg-page)', border: '1px solid var(--border-subtle)', color: 'var(--text-primary)', font: '400 14px/1.6 inherit', whiteSpace: 'pre-wrap' }}>{answer}</div>
        </div>
      </div>
      <div style={{ padding: 16, borderTop: '1px solid var(--border-subtle)', display: 'flex', gap: 10, alignItems: 'center' }}>
        <div style={{ flex: 1, height: 40, borderRadius: 999, border: '1px solid var(--border-default)', background: 'var(--bg-page)', padding: '0 16px', display: 'flex', alignItems: 'center', font: '400 14px/1 inherit', color: 'var(--text-tertiary)' }}>Votre question…</div>
        <span style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--primary)', color: 'var(--text-on-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="send" size={18} stroke={2} /></span>
      </div>
    </div>
  );
}

Object.assign(window, { VIEW, SpotBarStatic, WinStatic, SpotWindow, DockStatic, SpotStatic, AssistantStatic });
