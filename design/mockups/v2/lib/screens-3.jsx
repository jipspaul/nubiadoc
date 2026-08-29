// Nubia patient — group 3: onboarding, profil, réservation, wedge suite
// (signature/paiement/reçu), plan de traitement, passeport, suivi, notifications.
// Uses primitives from components.jsx + WEDGE/WedgeStepper/Reassurance/WedgeTopBar.

// shared little helpers
function NavTop({ title, trailing }) {
  return (
    <div style={{ padding: '52px 16px 10px', display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
      <IconButton name="chevronL" />
      <span className="t-title" style={{ flex: 1, textAlign: 'center', color: 'var(--text-primary)', fontWeight: 600 }}>{title}</span>
      {trailing || <div style={{ width: 44 }} />}
    </div>
  );
}
function Row({ icon, label, value, danger, last }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 0', borderBottom: last ? 'none' : '1px solid var(--border-subtle)' }}>
      <span style={{ width: 34, height: 34, borderRadius: 'var(--r-md)', flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: danger ? 'var(--danger-bg)' : 'var(--primary-subtle-bg)', color: danger ? 'var(--danger-fg)' : 'var(--primary-subtle-fg)' }}>
        <Icon name={icon} size={18} stroke={2} /></span>
      <span className="t-label" style={{ flex: 1, color: danger ? 'var(--danger-fg)' : 'var(--text-primary)' }}>{label}</span>
      {value && <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{value}</span>}
      {!danger && <span style={{ color: 'var(--text-tertiary)' }}><Icon name="chevronR" size={18} stroke={2} /></span>}
    </div>
  );
}
function GroupLabel({ children }) {
  return <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '20px 0 6px' }}>{children}</div>;
}

// ── 1. Connexion / onboarding ──
function ScreenConnexion({ dark }) {
  return (
    <Screen dark={dark}>
      <Scroll style={{ display: 'flex', flexDirection: 'column', padding: '0 28px' }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', textAlign: 'center', paddingTop: 90 }}>
          <span style={{ width: 64, height: 64, borderRadius: 19, background: 'var(--primary)', color: 'var(--text-on-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: 'var(--shadow-lg)' }}>
            <Icon name="plus" size={34} stroke={2.6} /></span>
          <div className="t-display" style={{ fontSize: 30, color: 'var(--text-primary)', marginTop: 22 }}>Nubia</div>
          <div className="t-body-lg" style={{ color: 'var(--text-secondary)', marginTop: 8, textWrap: 'balance' }}>Votre santé dentaire, en un seul endroit — trouvez, réservez, suivez.</div>
        </div>
        <div style={{ paddingBottom: 36 }}>
          <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 7 }}>Téléphone ou e-mail</div>
          <div style={{ height: 52, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', border: '1px solid var(--border-default)',
            display: 'flex', alignItems: 'center', padding: '0 14px', marginBottom: 12, color: 'var(--text-tertiary)' }} className="t-body-lg">
            06 12 34 56 78</div>
          <Button variant="primary" full iconRight="arrowR">Continuer</Button>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '18px 0' }}>
            <div style={{ flex: 1, height: 1, background: 'var(--border-subtle)' }} /><span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>ou</span><div style={{ flex: 1, height: 1, background: 'var(--border-subtle)' }} />
          </div>
          <Button variant="secondary" full icon="shield">Continuer avec FranceConnect</Button>
          <p className="t-caption" style={{ color: 'var(--text-tertiary)', textAlign: 'center', marginTop: 18, textWrap: 'pretty' }}>
            En continuant, vous acceptez les CGU et la politique de confidentialité (données de santé hébergées HDS).
          </p>
        </div>
      </Scroll>
    </Screen>
  );
}

// ── 2. Profil (5e onglet) ──
function ScreenProfil({ dark }) {
  return (
    <Screen dark={dark} nav="profile">
      <Header title="Profil" trailing={<IconButton name="sliders" />} />
      <Scroll style={{ padding: '4px 20px 8px' }}>
        <Card pad={16} style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 8 }}>
          <Avatar initials="CR" size={52} tone="brand" />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>Camille Rousseau</div>
            <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>camille.r@email.fr</div>
          </div>
          <Button size="sm" variant="secondary">Gérer</Button>
        </Card>

        <GroupLabel>Mon compte</GroupLabel>
        <Card pad={16} style={{ padding: '2px 16px' }}>
          <Row icon="user" label="Informations personnelles" />
          <Row icon="creditCard" label="Couverture santé" value="Régime général + MGEN" />
          <Row icon="users" label="Mes proches" value="2 enfants" />
          <Row icon="lock" label="Confidentialité & sécurité" last />
        </Card>

        <GroupLabel>Ma santé</GroupLabel>
        <Card pad={16} style={{ padding: '2px 16px' }}>
          <Row icon="check" label="Consentements" value="2 signés" />
          <Row icon="clipboard" label="Questionnaire de santé" />
          <Row icon="star" label="Mes avis" value="3" last />
        </Card>

        <GroupLabel>Préférences</GroupLabel>
        <Card pad={16} style={{ padding: '2px 16px' }}>
          <Row icon="bell" label="Notifications" />
          <Row icon="info" label="Infos pratiques du cabinet" last />
        </Card>

        <div style={{ height: 12 }} />
        <Card pad={16} style={{ padding: '2px 16px' }}>
          <Row icon="logout" label="Se déconnecter" danger last />
        </Card>
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

// ── 3. Réservation (motif → créneau → confirmation) ──
function ResaStepper({ step }) {
  const steps = ['Motif', 'Créneau', 'Confirmation'];
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 4px' }}>
      {steps.map((s, i) => (
        <React.Fragment key={i}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
            <span style={{ width: 22, height: 22, borderRadius: '50%', flexShrink: 0, background: i <= step ? 'var(--primary)' : 'var(--border-subtle)',
              color: i <= step ? 'var(--text-on-primary)' : 'var(--text-tertiary)', display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 12px/1 var(--font-ui)' }}>
              {i < step ? <Icon name="check" size={12} stroke={3} /> : i + 1}</span>
            <span className="t-caption" style={{ color: i <= step ? 'var(--text-primary)' : 'var(--text-tertiary)', fontWeight: i === step ? 600 : 400 }}>{s}</span>
          </div>
          {i < steps.length - 1 && <div style={{ flex: 1, height: 2, background: 'var(--border-subtle)' }} />}
        </React.Fragment>
      ))}
    </div>
  );
}
function ScreenReservation({ dark }) {
  const motifs = [{ l: 'Première consultation', m: '30 min', on: true }, { l: 'Contrôle / suivi', m: '20 min' }, { l: 'Détartrage', m: '30 min' }, { l: 'Urgence (douleur)', m: '15 min' }];
  const slots = ['09:00', '09:30', '11:15', '14:30', '15:00', '16:15'];
  return (
    <Screen dark={dark}>
      <NavTop title="Prendre rendez-vous" />
      <div style={{ padding: '0 20px 14px', flexShrink: 0 }}><ResaStepper step={1} /></div>
      <Scroll style={{ padding: '0 20px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderRadius: 'var(--r-lg)', background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', marginBottom: 18 }}>
          <Avatar initials="CL" size={40} tone="brand" />
          <div><div className="t-label" style={{ color: 'var(--text-primary)' }}>Dr Claire Lefèvre</div><div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Chirurgien-dentiste · Lyon 2e</div></div>
        </div>

        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Motif</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 20 }}>
          {motifs.map((m, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderRadius: 'var(--r-md)',
              background: m.on ? 'var(--primary-subtle-bg)' : 'var(--bg-surface)', border: '1px solid ' + (m.on ? 'var(--primary)' : 'var(--border-subtle)') }}>
              <span style={{ width: 20, height: 20, borderRadius: '50%', flexShrink: 0, border: '2px solid ' + (m.on ? 'var(--primary)' : 'var(--border-strong)'),
                display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{m.on && <span style={{ width: 10, height: 10, borderRadius: '50%', background: 'var(--primary)' }} />}</span>
              <span className="t-label" style={{ flex: 1, color: 'var(--text-primary)' }}>{m.l}</span>
              <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{m.m}</span>
            </div>
          ))}
        </div>

        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Mardi 3 juin · créneaux</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {slots.map((s, i) => (
            <span key={i} style={{ textAlign: 'center', padding: '12px 0', borderRadius: 'var(--r-sm)', font: '600 14px/1 var(--font-ui)',
              background: i === 3 ? 'var(--primary)' : 'var(--primary-subtle-bg)', color: i === 3 ? 'var(--text-on-primary)' : 'var(--primary-subtle-fg)' }}>{s}</span>
          ))}
        </div>
        <div style={{ height: 8 }} />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full iconRight="arrowR">Confirmer · mar. 3 juin à 14:30</Button>
      </div>
    </Screen>
  );
}
function ScreenReservationConfirm({ dark }) {
  return (
    <Screen dark={dark}>
      <NavTop title="Confirmation" />
      <Scroll style={{ padding: '0 24px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ textAlign: 'center', marginTop: 28 }}>
          <span style={{ width: 76, height: 76, borderRadius: '50%', background: 'var(--success-bg)', color: 'var(--success-fg)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="checkCircle" size={44} stroke={2} /></span>
          <div className="t-h2" style={{ color: 'var(--text-primary)', marginTop: 18 }}>Rendez-vous confirmé</div>
          <div className="t-body" style={{ color: 'var(--text-secondary)', marginTop: 6 }}>Il est ajouté à « Mes rendez-vous ».</div>
        </div>
        <Card pad={18} style={{ marginTop: 24 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
            <Avatar initials="CL" size={44} tone="brand" />
            <div><div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>Dr Claire Lefèvre</div><div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Première consultation · 30 min</div></div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <InfoRow icon="calendar">Mardi 3 juin 2025 · 14:30</InfoRow>
            <InfoRow icon="mapPin">12 rue de la République, Lyon 2e</InfoRow>
          </div>
        </Card>
        <div style={{ height: 8 }} />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Button variant="primary" full icon="qr">Préparer mon check-in</Button>
        <Button variant="ghost" full>Ajouter au calendrier</Button>
      </div>
    </Screen>
  );
}

// ── 4. Wedge suite : Signature → Paiement → Reçu ──
function ScreenSignature({ dark }) {
  return (
    <Screen dark={dark}>
      <WedgeTopBar />
      <div style={{ padding: '0 20px 16px', flexShrink: 0 }}><WedgeStepper step={0} /></div>
      <Scroll style={{ padding: '0 20px' }}>
        <Card pad={16} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div><div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{WEDGE.titre}</div><div className="t-caption" style={{ color: 'var(--text-secondary)' }}>{WEDGE.praticien}</div></div>
          <div className="t-h3 tabular" style={{ color: 'var(--text-primary)' }}>{WEDGE.total}</div>
        </Card>
        {['J\u2019ai lu et compris le devis et le plan de soins.', 'Je consens aux soins décrits (consentement éclairé).'].map((t, i) => (
          <div key={i} style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '10px 0' }}>
            <span style={{ width: 22, height: 22, borderRadius: 6, flexShrink: 0, background: 'var(--primary)', color: 'var(--text-on-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="check" size={14} stroke={3} /></span>
            <span className="t-body" style={{ color: 'var(--text-secondary)' }}>{t}</span>
          </div>
        ))}
        <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '16px 0 8px' }}>Votre signature</div>
        <div style={{ height: 130, borderRadius: 'var(--r-lg)', border: '1.5px dashed var(--border-strong)', background: 'var(--bg-surface)', position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ font: 'italic 28px/1 Georgia, serif', color: 'var(--text-primary)', opacity: 0.8 }}>Camille R.</span>
          <span className="t-micro" style={{ position: 'absolute', bottom: 8, right: 12, color: 'var(--text-tertiary)' }}>Signez ici</span>
        </div>
        <Reassurance />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full iconRight="arrowR">Valider ma signature</Button>
      </div>
    </Screen>
  );
}
function ScreenPaiement({ dark }) {
  const methods = [{ icon: 'checkCircle', l: 'Apple Pay', on: true }, { icon: 'creditCard', l: 'Carte bancaire' }, { icon: 'refresh', l: 'Payer en 3× sans frais' }];
  return (
    <Screen dark={dark}>
      <WedgeTopBar />
      <div style={{ padding: '0 20px 16px', flexShrink: 0 }}><WedgeStepper step={1} /></div>
      <Scroll style={{ padding: '0 20px' }}>
        <div style={{ textAlign: 'center', margin: '8px 0 20px' }}>
          <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Acompte à régler</div>
          <div className="t-display tabular" style={{ fontSize: 46, lineHeight: '54px', color: 'var(--text-primary)' }}>{WEDGE.acompte}</div>
          <div className="t-caption" style={{ color: 'var(--text-secondary)' }}>30 % de {WEDGE.reste} · solde à la pose</div>
        </div>
        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Moyen de paiement</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {methods.map((m, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px', borderRadius: 'var(--r-md)',
              background: m.on ? 'var(--primary-subtle-bg)' : 'var(--bg-surface)', border: '1px solid ' + (m.on ? 'var(--primary)' : 'var(--border-subtle)') }}>
              <span style={{ color: m.on ? 'var(--primary)' : 'var(--text-secondary)' }}><Icon name={m.icon} size={22} stroke={2} /></span>
              <span className="t-label" style={{ flex: 1, color: 'var(--text-primary)' }}>{m.l}</span>
              <span style={{ width: 20, height: 20, borderRadius: '50%', border: '2px solid ' + (m.on ? 'var(--primary)' : 'var(--border-strong)'), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                {m.on && <span style={{ width: 10, height: 10, borderRadius: '50%', background: 'var(--primary)' }} />}</span>
            </div>
          ))}
        </div>
        <Reassurance />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full icon="lock">Payer {WEDGE.acompte}</Button>
      </div>
    </Screen>
  );
}
function ScreenRecu({ dark }) {
  return (
    <Screen dark={dark}>
      <div style={{ padding: '0 20px 16px', flexShrink: 0, paddingTop: 52 }}><WedgeStepper step={2} /></div>
      <Scroll style={{ padding: '0 24px' }}>
        <div style={{ textAlign: 'center', marginTop: 20 }}>
          <span style={{ width: 80, height: 80, borderRadius: '50%', background: 'var(--success-bg)', color: 'var(--success-fg)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="checkCircle" size={46} stroke={2} /></span>
          <div className="t-h2" style={{ color: 'var(--text-primary)', marginTop: 18 }}>Paiement confirmé</div>
          <div className="t-body" style={{ color: 'var(--text-secondary)', marginTop: 6 }}>Acompte de <b style={{ color: 'var(--text-primary)' }}>{WEDGE.acompte}</b> réglé · devis signé.</div>
        </div>
        <Card pad={16} style={{ marginTop: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0' }} className="t-body"><span style={{ color: 'var(--text-tertiary)' }}>Reçu n°</span><span className="tabular" style={{ color: 'var(--text-primary)', fontWeight: 500 }}>NB-2025-0612</span></div>
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderTop: '1px solid var(--border-subtle)' }} className="t-body"><span style={{ color: 'var(--text-tertiary)' }}>Reste à régler</span><span className="tabular" style={{ color: 'var(--text-primary)', fontWeight: 500 }}>1 085 €</span></div>
        </Card>
        <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '18px 0 8px' }}>Votre prochain rendez-vous</div>
        <Card pad={14} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ width: 40, height: 40, borderRadius: 'var(--r-md)', background: 'var(--primary-subtle-bg)', color: 'var(--primary-subtle-fg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="calendar" size={20} stroke={2} /></span>
          <div style={{ flex: 1 }}><div className="t-label" style={{ color: 'var(--text-primary)' }}>Pose d'implant</div><div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Mar. 17 juin · 09:15</div></div>
        </Card>
        <div style={{ height: 8 }} />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Button variant="primary" full icon="download">Télécharger le reçu</Button>
        <Button variant="ghost" full>Voir mes rendez-vous</Button>
      </div>
    </Screen>
  );
}

// ── 5. Plan de traitement (🎭) ──
function ScreenPlanTraitement({ dark }) {
  const phases = [
    { n: '1', t: 'Bilan & radio panoramique', meta: 'Terminé · 14 avr.', tone: 'done' },
    { n: '2', t: 'Pose de l\u2019implant (dent 26)', meta: 'En cours · 17 juin', tone: 'now' },
    { n: '3', t: 'Pilier + couronne céramique', meta: 'Prévu · +3 mois', tone: 'next' },
    { n: '4', t: 'Contrôle d\u2019ostéo-intégration', meta: 'À planifier', tone: 'next' },
  ];
  return (
    <Screen dark={dark} nav="docs">
      <Header title="Plan de traitement" trailing={<Badge tone="info" icon="info">Suivi</Badge>} />
      <Scroll style={{ padding: '4px 20px 8px' }}>
        <Card pad={16} style={{ marginBottom: 18 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <span className="t-label" style={{ color: 'var(--text-primary)' }}>Avancement</span>
            <span className="t-caption" style={{ color: 'var(--text-secondary)' }}>1 / 4 phases</span>
          </div>
          <div style={{ height: 8, borderRadius: 'var(--r-full)', background: 'var(--border-subtle)', overflow: 'hidden' }}>
            <div style={{ width: '32%', height: '100%', background: 'var(--primary)' }} /></div>
        </Card>
        <div style={{ position: 'relative' }}>
          {phases.map((p, i) => {
            const c = p.tone === 'done' ? 'var(--success-fg)' : p.tone === 'now' ? 'var(--primary)' : 'var(--text-tertiary)';
            return (
              <div key={i} style={{ display: 'flex', gap: 14, paddingBottom: i < phases.length - 1 ? 18 : 0 }}>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                  <span style={{ width: 30, height: 30, borderRadius: '50%', flexShrink: 0, background: p.tone === 'next' ? 'var(--bg-surface)' : c, border: '2px solid ' + c,
                    color: p.tone === 'next' ? c : 'var(--text-on-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 13px/1 var(--font-ui)' }}>
                    {p.tone === 'done' ? <Icon name="check" size={15} stroke={3} /> : p.n}</span>
                  {i < phases.length - 1 && <div style={{ width: 2, flex: 1, background: 'var(--border-subtle)', marginTop: 4 }} />}
                </div>
                <div style={{ flex: 1, paddingTop: 3 }}>
                  <div className="t-label" style={{ color: 'var(--text-primary)' }}>{p.t}</div>
                  <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{p.meta}</div>
                </div>
              </div>
            );
          })}
        </div>
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

// ── 6. Passeport implantaire (premium sable, 🎭) ──
function ScreenPasseport({ dark }) {
  return (
    <Screen dark={dark}>
      <div style={{ background: 'var(--accent-100)', flexShrink: 0, paddingBottom: 22 }}>
        <div style={{ padding: '52px 16px 6px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ color: 'var(--accent-700)' }}><Icon name="chevronL" size={22} stroke={2} /></span>
          <span className="t-label" style={{ flex: 1, color: 'var(--accent-700)' }}>Passeport implantaire</span>
          <span style={{ color: 'var(--accent-700)' }}><Icon name="download" size={20} stroke={2} /></span>
        </div>
        <div style={{ padding: '14px 24px 0', textAlign: 'center' }}>
          <div style={{ font: '500 11px/1 var(--font-ui)', letterSpacing: 2, textTransform: 'uppercase', color: 'var(--accent-700)', marginBottom: 10 }}>Document de santé</div>
          <div style={{ font: '600 26px/1.2 var(--font-display)', color: 'var(--n-900)' }}>Camille Rousseau</div>
          <div className="t-caption" style={{ color: 'var(--accent-700)', marginTop: 6 }}>Implant titane · dent 26</div>
        </div>
      </div>
      <Scroll style={{ padding: '20px' }}>
        {[['Marque & référence', 'Nobel Biocare · N1 4.3×10'], ['Position', 'Maxillaire · dent 26'], ['Date de pose', '17 juin 2025'], ['Praticien', 'Dr Hugo Marin'], ['Garantie', '10 ans']].map((r, i, a) => (
          <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '13px 0', borderBottom: i < a.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
            <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{r[0]}</span>
            <span className="t-label" style={{ color: 'var(--text-primary)' }}>{r[1]}</span>
          </div>
        ))}
        <div style={{ display: 'flex', gap: 9, alignItems: 'center', marginTop: 14, padding: '12px 14px', borderRadius: 'var(--r-lg)', background: 'var(--accent-100)' }}>
          <span style={{ color: 'var(--accent-700)' }}><Icon name="shield" size={18} stroke={2} /></span>
          <span className="t-caption" style={{ color: 'var(--accent-700)', flex: 1 }}>Document officiel exportable, à présenter à tout praticien.</span>
        </div>
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full icon="download">Exporter en PDF</Button>
      </div>
    </Screen>
  );
}

// ── 7. Suivi & prévention ──
function ScreenSuivi({ dark }) {
  const tips = [{ icon: 'clock', t: 'Brossage 2×/jour, 2 minutes' }, { icon: 'check', t: 'Fil dentaire chaque soir' }, { icon: 'refresh', t: 'Contrôle tous les 6 mois' }];
  return (
    <Screen dark={dark} nav="profile">
      <Header title="Suivi & prévention" />
      <Scroll style={{ padding: '4px 20px 8px' }}>
        <div style={{ padding: 18, borderRadius: 'var(--r-xl)', background: 'var(--primary)', color: 'var(--text-on-primary)', marginBottom: 18 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}><Icon name="bell" size={18} stroke={2} /><span className="t-label">Prochain rappel</span></div>
          <div className="t-h3" style={{ color: 'var(--text-on-primary)' }}>Détartrage recommandé</div>
          <div className="t-caption" style={{ opacity: 0.9, marginTop: 4 }}>Dans 2 mois · août 2025 · Dr Lefèvre</div>
          <div style={{ marginTop: 14 }}><Button size="sm" variant="secondary" iconRight="arrowR">Reprendre rendez-vous</Button></div>
        </div>
        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Conseils d'hygiène</div>
        <Card pad={16} style={{ padding: '2px 16px' }}>
          {tips.map((t, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 0', borderBottom: i < tips.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
              <span style={{ color: 'var(--primary)' }}><Icon name={t.icon} size={18} stroke={2} /></span>
              <span className="t-body" style={{ color: 'var(--text-primary)' }}>{t.t}</span>
            </div>
          ))}
        </Card>
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

// ── 8. Centre de notifications ──
function ScreenNotifications({ dark }) {
  const groups = [
    { label: "Aujourd'hui", items: [
      { icon: 'document', tone: 'warning', t: 'Devis à signer', d: 'Plan de soins · Dr Lefèvre', time: '09:02', unread: true },
      { icon: 'message', tone: 'brand', t: 'Nouveau message', d: 'Cabinet Lefèvre vous a répondu', time: '08:40', unread: true },
    ] },
    { label: 'Cette semaine', items: [
      { icon: 'check', tone: 'success', t: 'Rendez-vous confirmé', d: 'Mar. 3 juin · 14:30', time: 'Lun.' },
      { icon: 'bell', tone: 'info', t: 'Rappel prévention', d: 'Détartrage recommandé', time: 'Dim.' },
    ] },
  ];
  return (
    <Screen dark={dark}>
      <Header title="Notifications" trailing={<IconButton name="sliders" />} />
      <Scroll style={{ padding: '4px 20px 8px' }}>
        {groups.map((g, gi) => (
          <div key={gi}>
            <div className="t-label" style={{ color: 'var(--text-secondary)', margin: gi ? '20px 0 6px' : '4px 0 6px' }}>{g.label}</div>
            <Card pad={16} style={{ padding: '2px 16px' }}>
              {g.items.map((n, i) => (
                <div key={i} style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '13px 0', borderBottom: i < g.items.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
                  <span style={{ width: 36, height: 36, borderRadius: 'var(--r-md)', flexShrink: 0, background: `var(--${n.tone === 'brand' ? 'primary-subtle' : n.tone}-bg)`, color: `var(--${n.tone === 'brand' ? 'primary-subtle' : n.tone}-fg)`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Icon name={n.icon} size={18} stroke={2} /></span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div className="t-label" style={{ color: 'var(--text-primary)' }}>{n.t}</div>
                    <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{n.d}</div>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
                    <span className="t-micro" style={{ color: 'var(--text-tertiary)' }}>{n.time}</span>
                    {n.unread && <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--primary)' }} />}
                  </div>
                </div>
              ))}
            </Card>
          </div>
        ))}
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

Object.assign(window, {
  NavTop, Row, GroupLabel, ScreenConnexion, ScreenProfil, ResaStepper, ScreenReservation, ScreenReservationConfirm,
  ScreenSignature, ScreenPaiement, ScreenRecu, ScreenPlanTraitement, ScreenPasseport, ScreenSuivi, ScreenNotifications,
});
