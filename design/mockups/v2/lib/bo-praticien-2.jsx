// Nubia back-office — app praticien : création de compte, inscription au service
// (RPPS, cabinet), profil public & créneaux, tableau de bord praticien.
// Reuses BOShell/Metric/Panel/AgendaDay/UrgentList/StatusPill + base primitives.

// ── Auth : connexion / création de compte (plein écran, sans sidebar) ──
function ScreenBOAuth({ dark }) {
  const props = ['Agenda fiable & sans no-show', 'Devis signés et acomptes en ligne', 'Marketplace : de nouveaux patients'];
  return (
    <div className={'nubia' + (dark ? ' nubia-dark' : '')} style={{ height: '100%', display: 'flex', background: 'var(--bg-page)', color: 'var(--text-primary)', fontFamily: 'var(--font-ui)' }}>
      {/* brand panel */}
      <div style={{ width: '44%', flexShrink: 0, padding: 44, display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
        background: 'linear-gradient(160deg, var(--brand-700), var(--brand-900))', color: '#fff' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ width: 32, height: 32, borderRadius: 9, background: 'rgba(255,255,255,0.16)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="plus" size={19} stroke={2.6} /></span>
          <span style={{ font: '600 19px/1 var(--font-ui)' }}>Nubia <span style={{ opacity: 0.7, fontSize: 13 }}>Pro</span></span>
        </div>
        <div>
          <div style={{ font: '600 30px/1.25 var(--font-ui)', letterSpacing: -0.4, marginBottom: 22, textWrap: 'balance' }}>Le logiciel qui fait gagner du temps à votre cabinet.</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            {props.map((p, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
                <span style={{ width: 24, height: 24, borderRadius: '50%', background: 'rgba(255,255,255,0.18)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Icon name="check" size={15} stroke={3} /></span>
                <span style={{ font: '400 15px/1.4 var(--font-ui)', opacity: 0.95 }}>{p}</span>
              </div>
            ))}
          </div>
        </div>
        <span style={{ font: '400 12px/1 var(--font-ui)', opacity: 0.6 }}>Données de santé hébergées HDS · conforme RGPD</span>
      </div>
      {/* form */}
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 40 }}>
        <div style={{ width: 380 }}>
          <div style={{ display: 'flex', gap: 2, padding: 4, background: 'var(--bg-page)', borderRadius: 'var(--r-md)', border: '1px solid var(--border-subtle)', marginBottom: 24 }}>
            {['Créer un compte', 'Se connecter'].map((t, i) => (
              <span key={i} style={{ flex: 1, textAlign: 'center', padding: '9px 0', borderRadius: 'var(--r-sm)', font: `${i === 0 ? 600 : 500} 13px/1 var(--font-ui)`,
                background: i === 0 ? 'var(--bg-surface)' : 'transparent', color: i === 0 ? 'var(--text-primary)' : 'var(--text-tertiary)', boxShadow: i === 0 ? 'var(--shadow-sm)' : 'none' }}>{t}</span>
            ))}
          </div>
          <div style={{ font: '600 22px/1.2 var(--font-ui)', color: 'var(--text-primary)', marginBottom: 6 }}>Créer votre compte</div>
          <div className="t-caption" style={{ color: 'var(--text-tertiary)', marginBottom: 20 }}>Quelques secondes — vous compléterez votre profil ensuite.</div>
          {[['Nom complet', 'Dr Hugo Marin'], ['E-mail professionnel', 'h.marin@cabinet-lyon.fr'], ['Mot de passe', '••••••••••']].map((f, i) => (
            <label key={i} style={{ display: 'block', marginBottom: 14 }}>
              <span className="t-label" style={{ color: 'var(--text-secondary)', display: 'block', marginBottom: 6 }}>{f[0]}</span>
              <div style={{ height: 46, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', border: '1px solid var(--border-default)', display: 'flex', alignItems: 'center', padding: '0 13px', color: 'var(--text-primary)' }} className="t-body">{f[1]}</div>
            </label>
          ))}
          <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '4px 0 6px' }}>Je suis</div>
          <div style={{ display: 'flex', gap: 8, marginBottom: 20 }}>
            {[{ l: 'Praticien', i: 'stethoscope', on: true }, { l: 'Secrétariat', i: 'users' }].map((r, j) => (
              <div key={j} style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8, padding: '11px 12px', borderRadius: 'var(--r-md)',
                background: r.on ? 'var(--primary-subtle-bg)' : 'var(--bg-surface)', border: '1px solid ' + (r.on ? 'var(--primary)' : 'var(--border-subtle)'), color: r.on ? 'var(--primary-subtle-fg)' : 'var(--text-secondary)' }}>
                <Icon name={r.i} size={18} stroke={2} /><span className="t-label">{r.l}</span>
              </div>
            ))}
          </div>
          <Button variant="primary" full iconRight="arrowR">Créer mon compte</Button>
          <p className="t-caption" style={{ color: 'var(--text-tertiary)', textAlign: 'center', marginTop: 14 }}>En continuant, vous acceptez les CGU Pro et la politique de confidentialité.</p>
        </div>
      </div>
    </div>
  );
}

// ── Inscription au service : stepper (identité → RPPS → cabinet → profil) ──
function StepRail({ steps }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      {steps.map((s, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderRadius: 'var(--r-md)', background: s.cur ? 'var(--primary-subtle-bg)' : 'transparent' }}>
          <span style={{ width: 28, height: 28, borderRadius: '50%', flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 13px/1 var(--font-ui)',
            background: s.done ? 'var(--primary)' : s.cur ? 'var(--bg-surface)' : 'var(--border-subtle)', color: s.done ? 'var(--text-on-primary)' : s.cur ? 'var(--primary)' : 'var(--text-tertiary)',
            border: s.cur ? '2px solid var(--primary)' : 'none' }}>{s.done ? <Icon name="check" size={15} stroke={3} /> : s.n}</span>
          <span style={{ font: `${s.cur ? 600 : 500} 14px/1 var(--font-ui)`, color: s.cur || s.done ? 'var(--text-primary)' : 'var(--text-tertiary)' }}>{s.l}</span>
        </div>
      ))}
    </div>
  );
}
function ScreenPratInscription({ dark }) {
  const steps = [{ n: 1, l: 'Identité', done: true }, { n: 2, l: 'Vérification RPPS', cur: true }, { n: 3, l: 'Cabinet & adresse' }, { n: 4, l: 'Profil public & créneaux' }];
  return (
    <div className={'nubia' + (dark ? ' nubia-dark' : '')} style={{ height: '100%', display: 'flex', flexDirection: 'column', background: 'var(--bg-page)', color: 'var(--text-primary)', fontFamily: 'var(--font-ui)' }}>
      <div style={{ height: 64, flexShrink: 0, borderBottom: '1px solid var(--border-subtle)', background: 'var(--bg-surface)', display: 'flex', alignItems: 'center', gap: 10, padding: '0 28px' }}>
        <span style={{ width: 28, height: 28, borderRadius: 8, background: 'var(--primary)', color: 'var(--text-on-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="plus" size={17} stroke={2.6} /></span>
        <span style={{ font: '600 16px/1 var(--font-ui)', flex: 1 }}>Rejoindre Nubia</span>
        <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Étape 2 / 4</span>
      </div>
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        <div style={{ width: 280, flexShrink: 0, borderRight: '1px solid var(--border-subtle)', padding: 20 }}><StepRail steps={steps} /></div>
        <div style={{ flex: 1, overflow: 'auto', padding: 36, display: 'flex', justifyContent: 'center' }}>
          <div style={{ width: 520 }}>
            <div style={{ font: '600 24px/1.2 var(--font-ui)', marginBottom: 6 }}>Vérifions votre identité professionnelle</div>
            <div className="t-body" style={{ color: 'var(--text-secondary)', marginBottom: 24 }}>Votre n° RPPS authentifie votre statut. Il ne sera jamais affiché publiquement.</div>
            <label style={{ display: 'block', marginBottom: 16 }}>
              <span className="t-label" style={{ color: 'var(--text-secondary)', display: 'block', marginBottom: 6 }}>Numéro RPPS</span>
              <div style={{ display: 'flex', gap: 10 }}>
                <div style={{ flex: 1, height: 48, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', border: '1px solid var(--border-default)', display: 'flex', alignItems: 'center', padding: '0 14px' }} className="t-body-lg tabular">10 100 234 567</div>
                <Button variant="secondary" icon="shield">Vérifier</Button>
              </div>
            </label>
            {/* verified card */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 16, borderRadius: 'var(--r-lg)', background: 'var(--primary-subtle-bg)', border: '1px solid var(--primary)', marginBottom: 24 }}>
              <Avatar initials="HM" size={48} tone="brand" />
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}><span className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>Dr Hugo Marin</span><Badge tone="brand" icon="shield">RPPS vérifié</Badge></div>
                <div className="t-caption" style={{ color: 'var(--primary-subtle-fg)' }}>Chirurgien-dentiste · inscrit à l'Ordre</div>
              </div>
            </div>
            <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Spécialité & actes proposés</div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 28 }}>
              {['Dentisterie générale', 'Implantologie', 'Parodontie', '+ Ajouter'].map((c, i) => (
                <Chip key={i} active={i < 2} icon={i === 3 ? 'plus' : undefined}>{c}</Chip>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 12 }}>
              <Button variant="secondary">Retour</Button>
              <Button variant="primary" iconRight="arrowR" style={{ flex: 1 }}>Continuer vers le cabinet</Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Profil public & ouverture de créneaux ──
function ScreenPratProfilPublic({ dark }) {
  const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  const grid = { Lun: [1, 1], Mar: [1, 1], Mer: [1, 0], Jeu: [1, 1], Ven: [1, 1], Sam: [1, 0], Dim: [0, 0] };
  return (
    <BOShell role="praticien" active="agenda" title="Profil public & disponibilités" sub="Ce que voient les patients sur la marketplace" dark={dark}
      actions={<Button size="sm" variant="primary" icon="check">Publier</Button>}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, alignItems: 'start' }}>
        <Panel title="Profil public" action={
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, font: '500 12px/1 var(--font-ui)', color: 'var(--primary)' }}>Visible
            <span style={{ width: 38, height: 22, borderRadius: 999, background: 'var(--primary)', position: 'relative' }}><span style={{ position: 'absolute', top: 2, right: 2, width: 18, height: 18, borderRadius: '50%', background: '#fff' }} /></span></span>}>
          <div style={{ padding: 18 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 16 }}>
              <Avatar initials="HM" size={52} tone="brand" />
              <div><div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>Dr Hugo Marin</div><div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Chirurgien-dentiste · Implantologie</div></div>
            </div>
            <FicheField label="Présentation" value="Diplômé de Lyon, 14 ans d'exercice…" />
            <div style={{ height: 12 }} />
            <div style={{ display: 'flex', gap: 8 }}><Badge tone="neutral">Secteur 1</Badge><Badge tone="brand" icon="check">Carte Vitale</Badge><Badge tone="neutral">PMR</Badge></div>
          </div>
        </Panel>
        <Panel title="Types de consultation">
          {[['Première consultation', '30 min'], ['Contrôle / suivi', '20 min'], ['Urgence', '15 min']].map((c, i, a) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 18px', borderBottom: i < a.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
              <span style={{ color: 'var(--primary)' }}><Icon name="clock" size={18} stroke={2} /></span>
              <span className="t-label" style={{ flex: 1, color: 'var(--text-primary)' }}>{c[0]}</span>
              <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{c[1]}</span>
            </div>
          ))}
          <div style={{ padding: '12px 18px' }}><span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--primary)', font: '600 13px/1 var(--font-ui)' }}><Icon name="plus" size={15} stroke={2.4} />Ajouter un motif</span></div>
        </Panel>
        <Panel title="Disponibilités hebdomadaires" style={{ gridColumn: '1 / -1' }}>
          <div style={{ padding: 18 }}>
            <div style={{ display: 'grid', gridTemplateColumns: '90px repeat(7, 1fr)', gap: 8, alignItems: 'center' }}>
              <span />{days.map(d => <span key={d} className="t-caption" style={{ textAlign: 'center', color: 'var(--text-secondary)', fontWeight: 600 }}>{d}</span>)}
              {['Matin', 'Après-midi'].map((period, pi) => (
                <React.Fragment key={pi}>
                  <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{period}</span>
                  {days.map(d => {
                    const on = grid[d][pi];
                    return <div key={d} style={{ height: 36, borderRadius: 'var(--r-sm)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                      background: on ? 'var(--primary-subtle-bg)' : 'var(--bg-page)', border: '1px solid ' + (on ? 'var(--primary)' : 'var(--border-subtle)'), color: 'var(--primary)' }}>
                      {on ? <Icon name="check" size={15} stroke={2.6} /> : null}</div>;
                  })}
                </React.Fragment>
              ))}
            </div>
          </div>
        </Panel>
      </div>
    </BOShell>
  );
}

// ── Tableau de bord praticien ──
function ScreenPratDash({ dark }) {
  const aValider = [
    { t: 'Devis « Plan implantaire » à envoyer', meta: 'Camille Rousseau · 2 060 €', cta: 'Envoyer' },
    { t: 'Compte-rendu opératoire à signer', meta: 'Marc Dubois · aujourd\u2019hui', cta: 'Signer' },
  ];
  return (
    <BOShell role="praticien" active="dash" title="Tableau de bord" sub="Dr Hugo Marin · mardi 3 juin · 09:12" dark={dark} actions={<LiveChip />}>
      <div style={{ display: 'flex', gap: 16 }}>
        <Metric icon="calendar" value="8" label="Mes RDV aujourd'hui" delta="+1" />
        <Metric icon="clock" value="2" label="Patients en salle" alert="info" />
        <Metric icon="document" value="3" label="Devis / CR à valider" alert="warning" />
        <Metric icon="message" value="2" label="Messages urgents" alert="danger" />
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1.7fr 1fr', gap: 20, marginTop: 20, alignItems: 'start' }}>
        <Panel title="Mon agenda" action={<span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Mardi 3 juin</span>}>
          <AgendaDay prats={['Dr Marin']} dark={dark} />
        </Panel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
          <Panel title="À valider">
            {aValider.map((a, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 18px', borderBottom: i < aValider.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
                <span style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flexShrink: 0, background: 'var(--warning-bg)', color: 'var(--warning-fg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="document" size={17} stroke={2} /></span>
                <div style={{ flex: 1, minWidth: 0 }}><div className="t-label" style={{ color: 'var(--text-primary)' }}>{a.t}</div><div className="t-micro" style={{ color: 'var(--text-tertiary)', fontWeight: 400 }}>{a.meta}</div></div>
                <Button size="sm" variant="secondary">{a.cta}</Button>
              </div>
            ))}
          </Panel>
          <Panel title="Messages urgents"><UrgentList /></Panel>
        </div>
      </div>
    </BOShell>
  );
}

Object.assign(window, { ScreenBOAuth, StepRail, ScreenPratInscription, ScreenPratProfilPublic, ScreenPratDash });
