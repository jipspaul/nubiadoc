// Nubia back-office — Praticien screens: Agenda, Messagerie priorisée,
// Fiche patient (clinique), Salle d'attente live. Clinical content visible here.

// ── Agenda praticien : sa journée + contexte clinique du patient suivant ──
function ScreenPratAgenda({ dark, chrome }) {
  return (
    <BOShell chrome={chrome} role="praticien" active="agenda" title="Mon agenda" sub="Dr Hugo Marin · mardi 3 juin" dark={dark}
      actions={<Button size="sm" variant="primary" icon="calendarPlus">Bloquer un créneau</Button>}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: 20, alignItems: 'start' }}>
        <Panel><AgendaDay prats={['Dr Marin']} dark={dark} /></Panel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Patient suivant" action={<StatusPill status="late" />}>
            <div style={{ padding: 18 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
                <Avatar initials="KS" size={44} tone="brand" />
                <div>
                  <div style={{ font: '600 16px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>Karim Saïdi</div>
                  <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>14:00 · Urgence · fracture</div>
                </div>
              </div>
              {/* clinical alert visible to praticien */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', borderRadius: 'var(--r-md)',
                background: 'var(--danger-bg)', color: 'var(--danger-fg)', marginBottom: 12 }}>
                <Icon name="alert" size={16} stroke={2.2} /><span style={{ font: '500 12px/1.3 var(--font-ui)' }}>Allergie pénicilline</span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                <FicheField label="Dernière visite" value="14 avr. · Bilan implantaire" />
                <FicheField label="En cours" value="Pose implant 26 — phase 2" />
              </div>
              <Button size="sm" variant="secondary" full style={{ marginTop: 14 }} icon="clipboard">Ouvrir le dossier</Button>
            </div>
          </Panel>
          <Panel title="Ma journée">
            <div style={{ padding: 18, display: 'flex', gap: 20 }}>
              <div><div style={{ font: '600 24px/1 var(--font-ui)', color: 'var(--text-primary)' }}>8</div>
                <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 5 }}>RDV</div></div>
              <div><div style={{ font: '600 24px/1 var(--font-ui)', color: 'var(--primary)' }}>5</div>
                <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 5 }}>Faits</div></div>
              <div><div style={{ font: '600 24px/1 var(--font-ui)', color: 'var(--warning-fg)' }}>1</div>
                <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 5 }}>En retard</div></div>
            </div>
          </Panel>
        </div>
      </div>
    </BOShell>
  );
}

// ── Messagerie priorisée (cabinet) — file triée, urgents en tête ──
const PRAT_MSGS = [
  { init: 'KS', name: 'Karim Saïdi', preview: 'Douleur vive après la pose, que faire ?', time: '8 min', urgent: true, unread: true, active: true, tone: 'brand' },
  { init: 'LF', name: 'Léa Fontaine', preview: 'Saignement léger ce matin', time: '24 min', urgent: true, unread: true, tone: 'sand' },
  { init: 'CR', name: 'Camille Rousseau', preview: 'Merci pour l\u2019ordonnance', time: '2 h', unread: false, tone: 'neutral' },
  { init: 'NK', name: 'Nadia Klein', preview: 'Puis-je décaler mon RDV ?', time: 'Hier', unread: false, tone: 'neutral' },
];

function ScreenPratMessagerie({ dark, chrome }) {
  return (
    <BOShell chrome={chrome} role="praticien" active="msg" title="Messagerie" sub="File priorisée · l'urgence remonte en tête" dark={dark}>
      <Panel pad={0} style={{ height: 600, display: 'flex', overflow: 'hidden' }}>
        {/* list */}
        <div style={{ width: 320, borderRight: '1px solid var(--border-subtle)', display: 'flex', flexDirection: 'column', flexShrink: 0 }}>
          <div style={{ padding: '12px 16px', borderBottom: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ font: '600 13px/1 var(--font-ui)', color: 'var(--text-tertiary)', textTransform: 'uppercase', letterSpacing: 0.4, flex: 1 }}>Conversations</span>
            <Badge tone="danger" icon="alert">2 urgents</Badge>
          </div>
          <div style={{ flex: 1, overflow: 'auto' }}>
            {PRAT_MSGS.map((m, i) => (
              <div key={i} style={{ display: 'flex', gap: 11, padding: '13px 16px', cursor: 'pointer',
                background: m.active ? 'var(--primary-subtle-bg)' : 'transparent',
                borderLeft: `3px solid ${m.active ? 'var(--primary)' : 'transparent'}`,
                borderBottom: '1px solid var(--border-subtle)' }}>
                <Avatar initials={m.init} size={38} tone={m.tone} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span style={{ font: `${m.unread ? 600 : 500} 13px/1 var(--font-ui)`, color: 'var(--text-primary)', flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{m.name}</span>
                    <span style={{ font: '400 11px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{m.time}</span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 4 }}>
                    {m.urgent && <Badge tone="danger" icon="alert">Urgent</Badge>}
                    <span style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{m.preview}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
        {/* thread */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          <div style={{ padding: '13px 18px', borderBottom: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', gap: 12 }}>
            <Avatar initials="KS" size={38} tone="brand" />
            <div style={{ flex: 1 }}>
              <div style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)' }}>Karim Saïdi</div>
              <div style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>RDV aujourd'hui 14:00 · Allergie pénicilline</div>
            </div>
            <Button size="sm" variant="secondary" icon="clipboard">Dossier</Button>
            <Button size="sm" variant="primary" icon="calendarPlus">Convertir en RDV</Button>
          </div>
          <div style={{ flex: 1, overflow: 'auto', padding: 20, background: 'var(--bg-page)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 14px', borderRadius: 'var(--r-md)', background: 'var(--danger-bg)',
              color: 'var(--danger-fg)', marginBottom: 18, font: '500 12px/1.3 var(--font-ui)' }}>
              <Icon name="alert" size={15} stroke={2.2} />Triage : marqué urgent par règle de mots-clés — aucune décision clinique automatique.
            </div>
            <div style={{ maxWidth: 420 }}>
              <Bubble time="13:48">Bonjour Docteur, j'ai une douleur vive depuis la pose de ce matin, est-ce normal ? Que dois-je faire ?</Bubble>
            </div>
            <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
              <div style={{ maxWidth: 420, width: '100%' }}>
                <Bubble me time="13:52">Bonjour Karim. Une gêne est fréquente les premières heures. Prenez le paracétamol prescrit (pas d'ibuprofène). Je vous vois à 14h, on contrôle ensemble.</Bubble>
              </div>
            </div>
          </div>
          {/* input */}
          <div style={{ padding: '12px 18px', borderTop: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ color: 'var(--text-tertiary)' }}><Icon name="paperclip" size={20} stroke={2} /></span>
            <div style={{ flex: 1, height: 40, borderRadius: 'var(--r-full)', background: 'var(--bg-page)', border: '1px solid var(--border-subtle)',
              display: 'flex', alignItems: 'center', padding: '0 14px', font: '400 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>Votre réponse…</div>
            <span style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--primary)', color: 'var(--text-on-primary)',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="send" size={18} stroke={2} /></span>
          </div>
        </div>
      </Panel>
    </BOShell>
  );
}

// ── Fiche patient clinique (odontogramme simple = carrés numérotés) ──
function ToothChart({ dark, chrome }) {
  // states keyed by tooth number
  const states = { 16: 'care', 26: 'implant', 36: 'treated', 37: 'treated', 14: 'treat', 46: 'treated' };
  const fills = {
    sain: { bg: 'var(--bg-surface)', bd: 'var(--border-default)', fg: 'var(--text-tertiary)' },
    treated: { bg: 'var(--primary-subtle-bg)', bd: 'var(--primary)', fg: 'var(--primary-subtle-fg)' },
    care: { bg: 'var(--info-bg)', bd: 'var(--info-fg)', fg: 'var(--info-fg)' },
    treat: { bg: 'var(--warning-bg)', bd: 'var(--warning-fg)', fg: 'var(--warning-fg)' },
    implant: { bg: 'var(--accent-100)', bd: 'var(--accent-500)', fg: 'var(--accent-700)' },
  };
  const upper = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
  const lower = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];
  const Cell = ({ n }) => {
    const s = fills[states[n] || 'sain'];
    return (
      <div style={{ width: 26, height: 30, borderRadius: 5, background: s.bg, border: `1.5px solid ${s.bd}`, color: s.fg,
        display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 10px/1 var(--font-ui)', flexShrink: 0 }}>{n}</div>
    );
  };
  const legend = [['sain', 'Sain'], ['treated', 'Soigné'], ['care', 'Surveillé'], ['treat', 'À traiter'], ['implant', 'Implant']];
  return (
    <div style={{ padding: 20 }}>
      <div style={{ display: 'flex', gap: 5, justifyContent: 'center' }}>{upper.map(n => <Cell key={n} n={n} />)}</div>
      <div style={{ height: 1, background: 'var(--border-subtle)', margin: '8px 0' }} />
      <div style={{ display: 'flex', gap: 5, justifyContent: 'center' }}>{lower.map(n => <Cell key={n} n={n} />)}</div>
      <div style={{ display: 'flex', gap: 16, justifyContent: 'center', marginTop: 18, flexWrap: 'wrap' }}>
        {legend.map(([k, label]) => (
          <span key={k} style={{ display: 'flex', alignItems: 'center', gap: 6, font: '400 12px/1 var(--font-ui)', color: 'var(--text-secondary)' }}>
            <span style={{ width: 13, height: 13, borderRadius: 3, background: fills[k].bg, border: `1.5px solid ${fills[k].bd}` }} />{label}
          </span>
        ))}
      </div>
    </div>
  );
}

// ── Journal clinique : notes manuelles (globales + liées à un acte) ──
function NotesJournal({ dark }) {
  const acts = [
    { dent: '26', label: 'Implant' },
    { dent: '14', label: 'Carie composite' },
    { dent: '36', label: 'Couronne' },
    { dent: '—', label: 'Parodonte' },
  ];
  const seed = [
    { id: 3, scope: 'act', ref: { dent: '26', label: 'Pose implant' }, date: '3 juin 2026 · 09:24', author: 'Dr Marin',
      text: 'Pose d\u2019implant 26 réalisée sans difficulté. Stabilité primaire 35 N·cm. Sutures 4/0, gants nitrile (allergie latex). Contrôle de cicatrisation à J+8.' },
    { id: 2, scope: 'global', ref: null, date: '14 avr. 2025', author: 'Dr Marin',
      text: 'Bilan implantaire favorable. Densité osseuse suffisante en secteur 2. Pose d\u2019implant 26 planifiée en deux temps. Pas de contre-indication hors allergie latex.' },
    { id: 1, scope: 'global', ref: null, date: '2 mars 2025', author: 'Dr Marin',
      text: 'Patient plutôt anxieux. Prévoir une explication détaillée avant chaque geste ; envisager sédation consciente si chirurgie longue.' },
  ];
  const [notes, setNotes] = React.useState(seed);
  const [scope, setScope] = React.useState('global');
  const [actSel, setActSel] = React.useState(0);
  const [draft, setDraft] = React.useState('');
  const add = () => {
    const t = draft.trim();
    if (!t) return;
    const ref = scope === 'act' ? acts[actSel] : null;
    setNotes([{ id: Date.now(), scope, ref, date: "À l'instant", author: 'Dr Marin', text: t, fresh: true }, ...notes]);
    setDraft('');
  };
  return (
    <Panel title="Journal clinique — notes & observations" style={{ gridColumn: '1 / -1' }}
      action={<span style={{ display: 'flex', alignItems: 'center', gap: 8 }}><span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{notes.length} entrées</span><Badge tone="neutral" icon="lock">Secret médical</Badge></span>}>
      {/* composer */}
      <div style={{ padding: 18, borderBottom: '1px solid var(--border-subtle)', background: 'var(--bg-page)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12, flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', gap: 4, padding: 4, background: 'var(--bg-surface)', borderRadius: 'var(--r-md)', border: '1px solid var(--border-subtle)' }}>
            {[['global', 'Observation générale', 'edit'], ['act', "Note d'acte", 'tooth']].map(([k, l, ic]) => {
              const on = scope === k;
              return (
                <span key={k} onClick={() => setScope(k)} style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '8px 14px', borderRadius: 'var(--r-sm)', cursor: 'pointer',
                  font: `${on ? 600 : 500} 13px/1 var(--font-ui)`, background: on ? 'var(--primary-subtle-bg)' : 'transparent', color: on ? 'var(--primary-subtle-fg)' : 'var(--text-tertiary)' }}>
                  <Icon name={ic} size={15} stroke={2} />{l}</span>
              );
            })}
          </div>
          {scope === 'act' && (
            <div style={{ display: 'flex', gap: 7, flexWrap: 'wrap' }}>
              {acts.map((a, i) => {
                const on = actSel === i;
                return (
                  <span key={i} onClick={() => setActSel(i)} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 34, padding: '0 12px', borderRadius: 'var(--r-full)', cursor: 'pointer',
                    font: '500 13px/1 var(--font-ui)', background: on ? 'var(--primary)' : 'var(--bg-surface)', color: on ? 'var(--text-on-primary)' : 'var(--text-secondary)',
                    border: `1px solid ${on ? 'transparent' : 'var(--border-subtle)'}` }}>
                    {a.dent !== '—' && <span style={{ font: '700 11px/1 var(--font-ui)', opacity: on ? 1 : 0.7 }}>{a.dent}</span>}{a.label}</span>
                );
              })}
            </div>
          )}
        </div>
        <textarea value={draft} onChange={e => setDraft(e.target.value)} spellCheck={false}
          placeholder={scope === 'act' ? `Note clinique sur la dent ${acts[actSel].dent} (${acts[actSel].label})…` : 'Saisir une observation clinique sur le patient…'}
          style={{ width: '100%', minHeight: 72, resize: 'none', border: '1px solid var(--border-default)', borderRadius: 'var(--r-md)', padding: 12, outline: 'none',
            background: 'var(--bg-surface)', font: '400 14px/1.6 var(--font-ui)', color: 'var(--text-primary)' }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 10 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', flex: 1 }}>
            <Icon name="lock" size={13} stroke={2} />Visible par le praticien uniquement · horodatée et signée</span>
          <Button size="sm" variant="primary" icon="plus" onClick={add}>Ajouter la note</Button>
        </div>
      </div>
      {/* timeline */}
      <div>
        {notes.map((n, i) => (
          <div key={n.id} style={{ display: 'flex', gap: 12, padding: '15px 18px', borderBottom: i < notes.length - 1 ? '1px solid var(--border-subtle)' : 'none',
            background: n.fresh ? 'var(--primary-subtle-bg)' : 'transparent' }}>
            <Avatar initials="HM" size={34} tone="brand" />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4, flexWrap: 'wrap' }}>
                <span style={{ font: '600 13px/1 var(--font-ui)', color: 'var(--text-primary)' }}>{n.author}</span>
                {n.scope === 'act'
                  ? <Badge tone="brand" icon="tooth">{n.ref.dent !== '—' ? `Dent ${n.ref.dent} · ${n.ref.label}` : n.ref.label}</Badge>
                  : <Badge tone="neutral" icon="edit">Observation</Badge>}
                <span style={{ marginLeft: 'auto', font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{n.date}</span>
              </div>
              <div style={{ font: '400 14px/1.6 var(--font-ui)', color: 'var(--text-secondary)' }}>{n.text}</div>
            </div>
          </div>
        ))}
      </div>
    </Panel>
  );
}

function ScreenPratFiche({ dark, chrome }) {
  const tabs = ['Clinique', 'Plan de traitement', 'Documents & radios', 'Historique'];
  const plan = [
    { step: '1', titre: 'Pose implant 26', meta: 'Phase 2/3 · aujourd\u2019hui', status: 'in_progress' },
    { step: '2', titre: 'Pilier + couronne céramique', meta: 'Prévu · à +3 mois', status: 'confirmed' },
    { step: '3', titre: 'Contrôle d\u2019ostéo-intégration', meta: 'À planifier', status: 'requested' },
  ];
  return (
    <BOShell chrome={chrome} role="praticien" active="patients" title="Dossier patient" sub="Vue clinique" dark={dark}
      actions={<Badge tone="brand" icon="stethoscope">Accès praticien</Badge>}>
      <Panel style={{ marginBottom: 20 }} pad={20}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <Avatar initials="MD" size={56} tone="brand" />
          <div style={{ flex: 1 }}>
            <div style={{ font: '600 20px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>Marc Dubois</div>
            <div style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>48 ans · Patient depuis 2017</div>
          </div>
          {/* clinical alerts */}
          <div style={{ display: 'flex', gap: 8 }}>
            <Badge tone="danger" icon="alert">Allergie latex</Badge>
            <Badge tone="warning" icon="info">Anticoagulants</Badge>
          </div>
          <Button size="sm" variant="primary" icon="edit">Nouvelle note</Button>
        </div>
        <div style={{ display: 'flex', gap: 24, marginTop: 20, borderBottom: '1px solid var(--border-subtle)', marginLeft: -20, marginRight: -20, padding: '0 20px' }}>
          {tabs.map((t, i) => (
            <span key={i} style={{ padding: '0 0 12px', font: `${i === 0 ? 600 : 500} 14px/1 var(--font-ui)`,
              color: i === 0 ? 'var(--primary)' : 'var(--text-tertiary)', borderBottom: `2px solid ${i === 0 ? 'var(--primary)' : 'transparent'}`, marginBottom: -1, cursor: 'pointer' }}>{t}</span>
          ))}
        </div>
      </Panel>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 360px', gap: 20, alignItems: 'start' }}>
        <Panel title="Schéma dentaire (odontogramme)" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--primary)' }}>Éditer</span>}>
          <ToothChart dark={dark} />
        </Panel>
        <Panel title="Plan de traitement">
          {plan.map((p, i) => (
            <div key={i} style={{ display: 'flex', gap: 12, padding: '14px 18px', borderBottom: i < plan.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
              <span style={{ width: 26, height: 26, borderRadius: '50%', flexShrink: 0, background: 'var(--primary-subtle-bg)', color: 'var(--primary-subtle-fg)',
                display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 12px/1 var(--font-ui)' }}>{p.step}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ font: '500 14px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>{p.titre}</div>
                <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>{p.meta}</div>
              </div>
              <StatusPill status={p.status} />
            </div>
          ))}
        </Panel>
        <NotesJournal dark={dark} />
      </div>
    </BOShell>
  );
}

// ── Salle d'attente live (praticien) ──
function ScreenPratSalle({ dark, chrome }) {
  const queue = [
    { h: '14:00', name: 'Karim Saïdi', init: 'KS', motif: 'Urgence · fracture', status: 'late', wait: '—' },
    { h: '14:30', name: 'Nadia Klein', init: 'NK', motif: 'Bilan implantaire', status: 'checked_in', wait: '4 min' },
    { h: '15:00', name: 'Sofia Lopez', init: 'SL', motif: 'Suivi post-op', status: 'confirmed', wait: '—' },
  ];
  return (
    <BOShell chrome={chrome} role="praticien" active="salle" title="Salle d'attente" sub="Dr Hugo Marin · file en temps réel" dark={dark}
      actions={<LiveChip label="SSE · live" />}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 340px', gap: 20, alignItems: 'start' }}>
        <Panel title="File d'attente">
          {queue.map((q, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 18px',
              borderBottom: i < queue.length - 1 ? '1px solid var(--border-subtle)' : 'none',
              background: q.status === 'late' ? 'var(--danger-bg)' : 'transparent' }}>
              <span style={{ font: '600 15px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums', width: 48 }}>{q.h}</span>
              <Avatar initials={q.init} size={40} tone="neutral" />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ font: '600 14px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{q.name}</div>
                <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>{q.motif}</div>
              </div>
              <span style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{q.wait !== '—' ? `attend ${q.wait}` : ''}</span>
              <StatusPill status={q.status} />
            </div>
          ))}
        </Panel>
        {/* current chair */}
        <Panel title="Au fauteuil">
          <div style={{ padding: 18 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
              <Avatar initials="JM" size={48} tone="brand" />
              <div>
                <div style={{ font: '600 16px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>Julien Mercier</div>
                <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>Salle 2 · depuis 09:05</div>
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16 }}><StatusPill status="in_progress" /><span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>Chirurgie · greffe</span></div>
            <Button variant="primary" full icon="bell">Appeler le patient suivant</Button>
            <div style={{ font: '400 12px/1.4 var(--font-ui)', color: 'var(--text-tertiary)', textAlign: 'center', marginTop: 10 }}>
              Notifie « C'est à vous » à Karim Saïdi (salle 2).
            </div>
          </div>
        </Panel>
      </div>
    </BOShell>
  );
}

Object.assign(window, {
  ScreenPratAgenda, PRAT_MSGS, ScreenPratMessagerie, ToothChart, NotesJournal, ScreenPratFiche, ScreenPratSalle,
});
