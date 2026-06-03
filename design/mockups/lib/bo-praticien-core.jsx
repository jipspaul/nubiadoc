// Nubia back-office — Praticien : le cœur de l'app.
// Tout ce dont le praticien a besoin pour gérer ses patients :
// tableau de bord, liste patients, consultation au fauteuil, plan de
// traitement & devis, ordonnance. Réutilise BOShell/Panel/Metric/AgendaDay/
// ToothChart/FicheField/WeekBars + primitives de base.

Object.assign(NB_ICONS, {
  tooth:   'M7 3c1.6 0 2.4 1 3 1s1.4-1 3-1c2.5 0 4 1.9 4 4.5 0 2-.7 3.6-1.3 6-.5 2-1 5-1.7 5-.9 0-.7-3-2-3s-1.1 3-2 3c-.7 0-1.2-3-1.7-5C7.7 11.1 7 9.5 7 7.5 7 5 5.5 3 7 3Z',
  syringe: 'M3 21l3-1 9-9M14 7l3 3M11 5l8 8M16 4l4 4M9 13l2 2',
  print:   'M7 8V3h10v5M7 17H5a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-2M7 14h10v6H7v-6Z',
  sign:    'M3 19c3 0 4-9 6-9s2 6 4 6 2-4 4-4 1 2 4 2M3 21h18',
});

// ── Shared patient banner (consultation / plan / ordonnance) ──
function PatientBanner({ init = 'MD', name = 'Marc Dubois', meta, alerts = [], trailing, tone = 'brand' }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
      <Avatar initials={init} size={52} tone={tone} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ font: '600 19px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{name}</div>
        <div style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>{meta}</div>
      </div>
      {alerts.length > 0 && <div style={{ display: 'flex', gap: 8 }}>{alerts.map((a, i) => <Badge key={i} tone={a.tone} icon={a.icon}>{a.label}</Badge>)}</div>}
      {trailing}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════
// 1 — Tableau de bord praticien (enrichi) : journée + clinique + production
// ════════════════════════════════════════════════════════════════
function ScreenPratDashboard({ dark, chrome }) {
  const week = [{ d: 'Lun', v: 1640 }, { d: 'Mar', v: 1980 }, { d: 'Mer', v: 1320 }, { d: 'Jeu', v: 2240 }, { d: 'Ven', v: 1760 }, { d: 'Sam', v: 720 }, { d: 'Dim', v: 0 }];
  const aValider = [
    { icon: 'document', tone: 'warning', t: 'Devis « Plan implantaire » à envoyer', meta: 'Camille Rousseau · 2 060 €', cta: 'Envoyer' },
    { icon: 'clipboard', tone: 'info', t: 'Compte-rendu opératoire à signer', meta: 'Marc Dubois · aujourd\u2019hui', cta: 'Signer' },
    { icon: 'pill', tone: 'brand', t: 'Ordonnance à valider', meta: 'Karim Saïdi · antalgique', cta: 'Valider' },
  ];
  return (
    <BOShell chrome={chrome} role="praticien" active="dash" title="Tableau de bord" sub="Dr Hugo Marin · mardi 3 juin · 09:12" dark={dark}
      actions={<LiveChip />}>
      <div style={{ display: 'flex', gap: 16 }}>
        <Metric icon="calendar" value="8" label="Mes RDV aujourd'hui" delta="+1" />
        <Metric icon="stethoscope" value="1" label="Au fauteuil" alert="info" />
        <Metric icon="clock" value="2" label="Patients en salle" alert="info" />
        <Metric icon="document" value="3" label="Devis / CR à valider" alert="warning" />
        <Metric icon="euro" value="1 980 €" label="Production du jour" delta="+9 %" />
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1.7fr 1fr', gap: 20, marginTop: 20, alignItems: 'start' }}>
        <Panel title="Mon agenda" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>Mardi 3 juin</span>}>
          <AgendaDay prats={['Dr Marin']} dark={dark} />
        </Panel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Patient suivant" action={<StatusPill status="late" />}>
            <div style={{ padding: 18 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
                <Avatar initials="KS" size={44} tone="brand" />
                <div><div style={{ font: '600 16px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>Karim Saïdi</div>
                  <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>14:00 · Urgence · fracture</div></div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', borderRadius: 'var(--r-md)',
                background: 'var(--danger-bg)', color: 'var(--danger-fg)', marginBottom: 12 }}>
                <Icon name="alert" size={16} stroke={2.2} /><span style={{ font: '500 12px/1.3 var(--font-ui)' }}>Allergie pénicilline</span>
              </div>
              <FicheField label="En cours" value="Pose implant 26 — phase 2" />
              <Button size="sm" variant="secondary" full style={{ marginTop: 14 }} icon="clipboard">Ouvrir le dossier</Button>
            </div>
          </Panel>
          <Panel title="À valider" action={<Badge tone="warning" icon="clock">3</Badge>}>
            {aValider.map((a, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 18px', borderBottom: i < aValider.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
                <span style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flexShrink: 0, background: `var(--${a.tone}-bg)`, color: `var(--${a.tone}-fg)`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={a.icon} size={17} stroke={2} /></span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ font: '500 13px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>{a.t}</div>
                  <div style={{ font: '400 12px/1.2 var(--font-ui)', color: 'var(--text-tertiary)' }}>{a.meta}</div>
                </div>
                <Button size="sm" variant="secondary">{a.cta}</Button>
              </div>
            ))}
          </Panel>
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginTop: 20, alignItems: 'start' }}>
        <Panel title="Ma production de la semaine" action={
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>
            9 660 € <Badge tone="success" icon="trendUp">+14 %</Badge></span>}>
          <div style={{ padding: '14px 18px 18px' }}><WeekBars data={week} max={2400} accentDays={['Jeu']} /></div>
        </Panel>
        <Panel title="Messages urgents" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--primary)' }}>Messagerie</span>}>
          <UrgentList />
        </Panel>
      </div>
    </BOShell>
  );
}

// ════════════════════════════════════════════════════════════════
// 2 — Mes patients : index des dossiers suivis par le praticien
// ════════════════════════════════════════════════════════════════
const PRAT_PATIENTS = [
  { init: 'MD', name: 'Marc Dubois', age: '48 ans', last: 'Pose implant 26', lastDate: 'Aujourd\u2019hui', plan: 'Implant · 2/3', planTone: 'brand', next: '3 juin', solde: '1 550 €', soldeDue: true, alert: 'Latex' },
  { init: 'CR', name: 'Camille Rousseau', age: '34 ans', last: 'Contrôle annuel', lastDate: '02/06', plan: 'Devis à signer', planTone: 'warning', next: '—', solde: '465 €', soldeDue: true },
  { init: 'KS', name: 'Karim Saïdi', age: '29 ans', last: 'Urgence fracture', lastDate: '01/06', plan: 'En cours', planTone: 'info', next: '14:00', solde: '0 €', alert: 'Pénicilline' },
  { init: 'LF', name: 'Léa Fontaine', age: '41 ans', last: 'Consultation douleur', lastDate: '30/05', plan: 'À diagnostiquer', planTone: 'neutral', next: '3 juin', solde: '0 €' },
  { init: 'NK', name: 'Nadia Klein', age: '57 ans', last: 'Bilan implantaire', lastDate: '24/05', plan: 'Devis expiré', planTone: 'danger', next: '—', solde: '0 €' },
  { init: 'SL', name: 'Sofia Lopez', age: '36 ans', last: 'Suivi post-op', lastDate: '20/05', plan: 'Cicatrisation', planTone: 'success', next: '15:00', solde: '0 €' },
];
function PlanTag({ tone, children }) {
  const map = { brand: 'brand', warning: 'warning', info: 'info', danger: 'danger', success: 'success', neutral: 'neutral' };
  return <Badge tone={map[tone]} icon={tone === 'danger' ? 'alert' : tone === 'success' ? 'check' : tone === 'warning' ? 'clock' : 'stethoscope'}>{children}</Badge>;
}
function ScreenPratPatients({ dark, chrome }) {
  const cols = '1.6fr 90px 1.3fr 150px 90px 100px';
  return (
    <BOShell chrome={chrome} role="praticien" active="patients" title="Mes patients" sub="Dossiers que vous suivez · 248 patients actifs" dark={dark}
      actions={<Button size="sm" variant="primary" icon="plus">Nouveau patient</Button>}>
      <div style={{ display: 'flex', gap: 16, marginBottom: 20 }}>
        <Metric icon="users" value="248" label="Patients actifs" />
        <Metric icon="stethoscope" value="17" label="Traitements en cours" alert="info" />
        <Metric icon="clock" value="5" label="À revoir ce mois" alert="warning" />
        <Metric icon="document" value="3" label="Devis en attente" alert="warning" />
      </div>
      <Panel title="Tous mes patients" action={
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <div style={{ width: 200, height: 34, borderRadius: 'var(--r-md)', background: 'var(--bg-page)', border: '1px solid var(--border-subtle)',
            display: 'flex', alignItems: 'center', gap: 8, padding: '0 10px', color: 'var(--text-tertiary)' }}>
            <Icon name="search" size={15} stroke={2} /><span style={{ font: '400 12px/1 var(--font-ui)' }}>Rechercher…</span></div>
          <Chip active>Tous</Chip><Chip>En traitement</Chip><Chip>À revoir</Chip>
        </div>}>
        <div style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '11px 18px',
          font: '600 11px/1 var(--font-ui)', letterSpacing: 0.4, textTransform: 'uppercase', color: 'var(--text-tertiary)', borderBottom: '1px solid var(--border-subtle)' }}>
          <span>Patient</span><span>Âge</span><span>Dernier acte</span><span>Plan en cours</span><span>Prochain</span><span>Solde</span>
        </div>
        {PRAT_PATIENTS.map((p, i) => (
          <div key={i} style={{ display: 'grid', gridTemplateColumns: cols, gap: 12, padding: '13px 18px', alignItems: 'center',
            borderBottom: i < PRAT_PATIENTS.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              <Avatar initials={p.init} size={32} tone="neutral" />
              <span style={{ minWidth: 0 }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ font: '600 14px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{p.name}</span>
                  {p.alert && <Badge tone="danger" icon="alert">{p.alert}</Badge>}
                </span>
              </span>
            </span>
            <span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>{p.age}</span>
            <span style={{ minWidth: 0 }}>
              <div style={{ font: '500 13px/1.2 var(--font-ui)', color: 'var(--text-primary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.last}</div>
              <div style={{ font: '400 12px/1.2 var(--font-ui)', color: 'var(--text-tertiary)' }}>{p.lastDate}</div>
            </span>
            <span><PlanTag tone={p.planTone}>{p.plan}</PlanTag></span>
            <span style={{ font: '500 13px/1 var(--font-ui)', color: p.next === '—' ? 'var(--text-tertiary)' : 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>{p.next}</span>
            <span style={{ font: '600 13px/1 var(--font-ui)', color: p.soldeDue ? 'var(--danger-fg)' : 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{p.solde}</span>
          </div>
        ))}
      </Panel>
    </BOShell>
  );
}

// ════════════════════════════════════════════════════════════════
// 3 — Consultation au fauteuil : LE cœur — gérer le patient en soin
// ════════════════════════════════════════════════════════════════
function SessionTimer() {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '6px 12px 6px 10px', borderRadius: 'var(--r-full)',
      background: 'var(--primary)', color: 'var(--text-on-primary)', font: '600 13px/1 var(--font-ui)', fontVariantNumeric: 'tabular-nums' }}>
      <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'currentColor' }} />Séance · 14:32
    </span>
  );
}
function ScreenPratConsultation({ dark, chrome }) {
  const actes = [
    { code: 'LBLA001', label: 'Anesthésie locale para-apicale', dent: '26', tarif: 'incluse', done: true },
    { code: 'HBQK002', label: 'Radiographie rétro-alvéolaire', dent: '26', tarif: '—', done: true },
    { code: 'HBLD036', label: 'Pose d\u2019implant intra-osseux', dent: '26', tarif: '950 €', done: true },
    { code: 'HBGD016', label: 'Sutures', dent: '26', tarif: 'incluses', done: false, current: true },
  ];
  const antecedents = ['Bruxisme nocturne (gouttière)', 'Parodontite traitée 2021', 'Tabac : non'];
  const actions = [
    { icon: 'plus', label: 'Ajouter un acte', variant: 'secondary' },
    { icon: 'pill', label: 'Prescrire une ordonnance', variant: 'secondary' },
    { icon: 'image', label: 'Joindre une radio', variant: 'secondary' },
    { icon: 'arrowR', label: 'Étape suivante du plan', variant: 'secondary' },
  ];
  return (
    <BOShell chrome={chrome} role="praticien" active="soins" title="Consultation en cours" sub="Salle 2 · Dr Hugo Marin" dark={dark}
      actions={<SessionTimer />}>
      <Panel style={{ marginBottom: 20 }} pad={18}>
        <PatientBanner init="MD" name="Marc Dubois" meta="48 ans · RDV 09:00 · Pose implant 26 — phase 2/3"
          alerts={[{ tone: 'danger', icon: 'alert', label: 'Allergie latex' }, { tone: 'warning', icon: 'info', label: 'Anticoagulants' }]}
          trailing={<StatusPill status="in_progress" />} />
      </Panel>
      <div style={{ display: 'grid', gridTemplateColumns: '300px 1fr 280px', gap: 20, alignItems: 'start' }}>
        {/* contexte clinique */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Contexte clinique">
            <div style={{ padding: 18, display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderRadius: 'var(--r-md)', background: 'var(--primary-subtle-bg)' }}>
                <span style={{ width: 38, height: 38, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', color: 'var(--primary)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', font: '700 14px/1 var(--font-ui)' }}>26</span>
                <div><div style={{ font: '600 13px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>Dent traitée</div>
                  <div style={{ font: '400 12px/1.2 var(--font-ui)', color: 'var(--primary-subtle-fg)' }}>1ère molaire · maxillaire G</div></div>
              </div>
              <FicheField label="Antécédents" value={<div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {antecedents.map((a, i) => <span key={i} style={{ font: '400 13px/1.3 var(--font-ui)', color: 'var(--text-secondary)' }}>· {a}</span>)}</div>} />
              <div style={{ height: 1, background: 'var(--border-subtle)' }} />
              <FicheField label="Dernière note · 14 avr." value="Densité osseuse suffisante en secteur 2. Pose planifiée en deux temps." />
            </div>
          </Panel>
        </div>
        {/* actes de la séance + note */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Actes de la séance" action={<span style={{ font: '500 13px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>4 actes · 950 €</span>}>
            {actes.map((a, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 18px',
                borderBottom: i < actes.length - 1 ? '1px solid var(--border-subtle)' : 'none',
                background: a.current ? 'var(--primary-subtle-bg)' : 'transparent' }}>
                <span style={{ width: 26, height: 26, borderRadius: '50%', flexShrink: 0,
                  background: a.done ? 'var(--primary)' : 'var(--bg-surface)', color: a.done ? 'var(--text-on-primary)' : 'var(--primary)',
                  border: a.done ? 'none' : '1.5px solid var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {a.done ? <Icon name="check" size={15} stroke={3} /> : <Icon name="clock" size={13} stroke={2.2} />}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ font: '500 14px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{a.label}</div>
                  <div style={{ font: '400 12px/1.2 var(--font-ui)', color: 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{a.code} · dent {a.dent}</div>
                </div>
                <span style={{ font: '600 13px/1 var(--font-ui)', color: a.tarif.includes('€') ? 'var(--text-primary)' : 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{a.tarif}</span>
              </div>
            ))}
            <div style={{ padding: '12px 18px' }}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, color: 'var(--primary)', font: '600 13px/1 var(--font-ui)', cursor: 'pointer' }}>
                <Icon name="plus" size={15} stroke={2.4} />Ajouter un acte (CCAM)</span>
            </div>
          </Panel>
          <Panel title="Note clinique de la séance" action={<Badge tone="neutral" icon="lock">Secret médical</Badge>}>
            <div style={{ padding: 18 }}>
              <textarea defaultValue={"Pose d'implant 26 sans difficulté. Stabilité primaire satisfaisante (35 N·cm). Gants nitrile (allergie latex). Sutures 4/0. Contrôle de cicatrisation à J+8."}
                spellCheck={false} style={{ width: '100%', minHeight: 96, resize: 'none', border: '1px solid var(--border-subtle)', borderRadius: 'var(--r-md)',
                  padding: 12, outline: 'none', background: 'var(--bg-page)', font: '400 14px/1.6 var(--font-ui)', color: 'var(--text-primary)' }} />
            </div>
          </Panel>
        </div>
        {/* actions */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Actions">
            <div style={{ padding: 16, display: 'flex', flexDirection: 'column', gap: 9 }}>
              {actions.map((a, i) => <Button key={i} size="sm" variant={a.variant} full icon={a.icon} style={{ justifyContent: 'flex-start' }}>{a.label}</Button>)}
              <div style={{ height: 1, background: 'var(--border-subtle)', margin: '4px 0' }} />
              <Button variant="primary" full icon="check">Terminer & facturer</Button>
            </div>
          </Panel>
          <Panel title="Prochaine étape">
            <div style={{ padding: 18 }}>
              <div style={{ display: 'flex', gap: 12 }}>
                <span style={{ width: 26, height: 26, borderRadius: '50%', flexShrink: 0, background: 'var(--primary-subtle-bg)', color: 'var(--primary-subtle-fg)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 12px/1 var(--font-ui)' }}>3</span>
                <div><div style={{ font: '500 14px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>Pilier + couronne céramique</div>
                  <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>À +3 mois · ostéo-intégration</div></div>
              </div>
              <Button size="sm" variant="secondary" full icon="calendarPlus" style={{ marginTop: 14 }}>Programmer le RDV</Button>
            </div>
          </Panel>
        </div>
      </div>
    </BOShell>
  );
}

// ════════════════════════════════════════════════════════════════
// 4 — Plan de traitement & devis : planifier les soins, chiffrer
// ════════════════════════════════════════════════════════════════
function ScreenPratPlan({ dark, chrome }) {
  const phases = [
    { titre: 'Phase 1 · Assainissement', status: 'done', actes: [
      { label: 'Détartrage deux arcades', dent: '—', base: '28,92 €', montant: '60 €' },
      { label: 'Traitement carie composite', dent: '14', base: '40,97 €', montant: '90 €' },
    ] },
    { titre: 'Phase 2 · Chirurgie implantaire', status: 'in_progress', actes: [
      { label: 'Pose d\u2019implant intra-osseux', dent: '26', base: 'Non remb.', montant: '950 €' },
      { label: 'Greffe osseuse pré-implantaire', dent: '26', base: 'Non remb.', montant: '420 €' },
    ] },
    { titre: 'Phase 3 · Prothèse', status: 'requested', actes: [
      { label: 'Pilier implantaire', dent: '26', base: 'Non remb.', montant: '280 €' },
      { label: 'Couronne céramo-céramique', dent: '26', base: '120 €', montant: '780 €' },
    ] },
  ];
  return (
    <BOShell chrome={chrome} role="praticien" active="devis" title="Plan de traitement" sub="Construction du devis · proposé au patient" dark={dark}
      actions={<Button size="sm" variant="secondary" icon="plus">Ajouter une phase</Button>}>
      <Panel style={{ marginBottom: 20 }} pad={18}>
        <PatientBanner init="MD" name="Marc Dubois" meta="48 ans · Patient depuis 2017 · Plan implantaire 26"
          alerts={[{ tone: 'brand', icon: 'stethoscope', label: '3 phases · 8 actes' }]} />
      </Panel>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 340px', gap: 20, alignItems: 'start' }}>
        <Panel title="Phases & actes du plan">
          {phases.map((ph, pi) => (
            <div key={pi}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '13px 18px', background: 'var(--bg-page)', borderBottom: '1px solid var(--border-subtle)' }}>
                <span style={{ font: '600 13px/1 var(--font-ui)', color: 'var(--text-primary)', flex: 1 }}>{ph.titre}</span>
                <StatusPill status={ph.status} />
              </div>
              {ph.actes.map((a, ai) => (
                <div key={ai} style={{ display: 'grid', gridTemplateColumns: '1fr 60px 100px 90px', gap: 12, padding: '13px 18px', alignItems: 'center',
                  borderBottom: '1px solid var(--border-subtle)' }}>
                  <span style={{ font: '500 14px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{a.label}</span>
                  <span style={{ font: '500 12px/1 var(--font-ui)', color: 'var(--text-tertiary)' }}>dent {a.dent}</span>
                  <span style={{ font: '400 12px/1 var(--font-ui)', color: 'var(--text-tertiary)', fontVariantNumeric: 'tabular-nums' }}>{a.base}</span>
                  <span style={{ font: '600 14px/1 var(--font-ui)', color: 'var(--text-primary)', textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{a.montant}</span>
                </div>
              ))}
            </div>
          ))}
          <div style={{ padding: '12px 18px' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, color: 'var(--primary)', font: '600 13px/1 var(--font-ui)', cursor: 'pointer' }}>
              <Icon name="plus" size={15} stroke={2.4} />Ajouter un acte</span>
          </div>
        </Panel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Récapitulatif financier">
            <div style={{ padding: 18 }}>
              {[['Total des soins', '3 580 €', false], ['Base remboursement Sécu', '− 190 €', false], ['Estimation mutuelle (MGEN)', '− 640 €', false]].map((r, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', padding: '9px 0', borderBottom: '1px solid var(--border-subtle)' }}>
                  <span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-secondary)' }}>{r[0]}</span>
                  <span style={{ font: '500 14px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>{r[1]}</span>
                </div>
              ))}
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 14, padding: 16, borderRadius: 'var(--r-lg)', background: 'var(--primary)', color: 'var(--text-on-primary)' }}>
                <span style={{ font: '500 13px/1 var(--font-ui)', opacity: 0.9 }}>Reste à charge</span>
                <span style={{ font: '700 24px/1 var(--font-ui)', fontVariantNumeric: 'tabular-nums' }}>2 750 €</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 12 }}>
                <span style={{ font: '400 13px/1 var(--font-ui)', color: 'var(--text-secondary)' }}>Acompte demandé (30 %)</span>
                <span style={{ font: '600 16px/1 var(--font-ui)', color: 'var(--text-primary)', fontVariantNumeric: 'tabular-nums' }}>825 €</span>
              </div>
            </div>
          </Panel>
          <Panel pad={16}>
            <Button variant="primary" full icon="send">Envoyer le devis au patient</Button>
            <Button variant="secondary" full icon="calendarPlus" style={{ marginTop: 9 }}>Programmer les RDV du plan</Button>
            <div style={{ font: '400 12px/1.5 var(--font-ui)', color: 'var(--text-tertiary)', textAlign: 'center', marginTop: 12 }}>
              Signature électronique · acompte réglable en ligne
            </div>
          </Panel>
        </div>
      </div>
    </BOShell>
  );
}

// ════════════════════════════════════════════════════════════════
// 5 — Ordonnance : prescription sécurisée (contrôle allergie)
// ════════════════════════════════════════════════════════════════
function ScreenPratOrdonnance({ dark, chrome }) {
  const meds = [
    { name: 'Paracétamol 1 g', form: 'comprimé', poso: '1 cp × 3 / jour si douleur', duree: '5 jours', qsp: '15 cp' },
    { name: 'Amoxicilline 1 g', form: 'comprimé', poso: 'Contre-indiqué', duree: '—', qsp: '—', blocked: true },
    { name: 'Spiramycine 1,5 M UI', form: 'comprimé', poso: '2 cp × 2 / jour', duree: '6 jours', qsp: '24 cp', alt: true },
    { name: 'Bain de bouche chlorhexidine', form: 'solution', poso: '2 / jour après brossage', duree: '7 jours', qsp: '1 flacon' },
  ];
  return (
    <BOShell chrome={chrome} role="praticien" active="patients" title="Ordonnance" sub="Prescription · Karim Saïdi" dark={dark}
      actions={<Badge tone="brand" icon="stethoscope">Dr Hugo Marin · RPPS vérifié</Badge>}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: 20, alignItems: 'start' }}>
        <Panel pad={0}>
          {/* prescription document head */}
          <div style={{ padding: 22, borderBottom: '1px solid var(--border-subtle)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <div style={{ font: '600 16px/1.2 var(--font-display, var(--font-ui))', color: 'var(--text-primary)' }}>Dr Hugo Marin</div>
                <div style={{ font: '400 12px/1.5 var(--font-ui)', color: 'var(--text-tertiary)', marginTop: 2 }}>Chirurgien-dentiste · Cabinet Lyon<br />RPPS 10 100 234 567</div>
              </div>
              <div style={{ textAlign: 'right', font: '400 12px/1.5 var(--font-ui)', color: 'var(--text-tertiary)' }}>Lyon, le 3 juin 2026<br />
                <span style={{ font: '500 13px/1.5 var(--font-ui)', color: 'var(--text-primary)' }}>Karim Saïdi · 29 ans</span></div>
            </div>
          </div>
          {/* allergy guard */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 22px', background: 'var(--danger-bg)', color: 'var(--danger-fg)' }}>
            <Icon name="shield" size={17} stroke={2.2} /><span style={{ font: '500 13px/1.3 var(--font-ui)' }}>Allergie pénicilline au dossier — les bêta-lactamines sont automatiquement bloquées.</span>
          </div>
          {/* med lines */}
          {meds.map((m, i) => (
            <div key={i} style={{ display: 'flex', gap: 14, padding: '16px 22px', borderBottom: i < meds.length - 1 ? '1px solid var(--border-subtle)' : 'none',
              opacity: m.blocked ? 0.55 : 1, background: m.alt ? 'var(--primary-subtle-bg)' : 'transparent' }}>
              <span style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flexShrink: 0,
                background: m.blocked ? 'var(--danger-bg)' : 'var(--primary-subtle-bg)', color: m.blocked ? 'var(--danger-fg)' : 'var(--primary)',
                display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={m.blocked ? 'x' : 'pill'} size={18} stroke={2} /></span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ font: '600 14px/1.3 var(--font-ui)', color: 'var(--text-primary)', textDecoration: m.blocked ? 'line-through' : 'none' }}>{m.name}</span>
                  {m.blocked && <Badge tone="danger" icon="alert">Bloqué · allergie</Badge>}
                  {m.alt && <Badge tone="success" icon="check">Alternative</Badge>}
                </div>
                <div style={{ font: '400 13px/1.4 var(--font-ui)', color: 'var(--text-secondary)', marginTop: 3 }}>{m.poso}</div>
              </div>
              <div style={{ textAlign: 'right', flexShrink: 0 }}>
                <div style={{ font: '500 13px/1.3 var(--font-ui)', color: 'var(--text-primary)' }}>{m.duree}</div>
                <div style={{ font: '400 12px/1.3 var(--font-ui)', color: 'var(--text-tertiary)' }}>{m.qsp}</div>
              </div>
            </div>
          ))}
          <div style={{ padding: '14px 22px' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, color: 'var(--primary)', font: '600 13px/1 var(--font-ui)', cursor: 'pointer' }}>
              <Icon name="plus" size={15} stroke={2.4} />Ajouter un médicament</span>
          </div>
        </Panel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="Contrôle de sécurité">
            <div style={{ padding: 18, display: 'flex', flexDirection: 'column', gap: 12 }}>
              {[['Allergies du patient', 'Pénicilline bloquée', 'danger', 'check'], ['Interactions médicamenteuses', 'Aucune détectée', 'success', 'check'], ['Posologies', 'Adaptées au poids', 'success', 'check']].map((r, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span style={{ width: 28, height: 28, borderRadius: '50%', flexShrink: 0, background: `var(--${r[2]}-bg)`, color: `var(--${r[2]}-fg)`,
                    display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={r[3]} size={15} stroke={2.4} /></span>
                  <div style={{ flex: 1 }}><div style={{ font: '500 13px/1.2 var(--font-ui)', color: 'var(--text-primary)' }}>{r[0]}</div>
                    <div style={{ font: '400 12px/1.2 var(--font-ui)', color: 'var(--text-tertiary)' }}>{r[1]}</div></div>
                </div>
              ))}
            </div>
          </Panel>
          <Panel pad={16}>
            <Button variant="primary" full icon="sign">Signer électroniquement</Button>
            <div style={{ display: 'flex', gap: 9, marginTop: 9 }}>
              <Button variant="secondary" full icon="send">Envoyer</Button>
              <Button variant="secondary" full icon="print">Imprimer</Button>
            </div>
            <div style={{ font: '400 12px/1.5 var(--font-ui)', color: 'var(--text-tertiary)', textAlign: 'center', marginTop: 12 }}>
              Ordonnance numérique · transmise à la pharmacie au choix du patient
            </div>
          </Panel>
        </div>
      </div>
    </BOShell>
  );
}

Object.assign(window, {
  PatientBanner, ScreenPratDashboard, PRAT_PATIENTS, PlanTag, ScreenPratPatients,
  SessionTimer, ScreenPratConsultation, ScreenPratPlan, ScreenPratOrdonnance,
});
