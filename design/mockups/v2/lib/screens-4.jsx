// Nubia patient — group 4: recherche de RDV (disponibilités) + préparation du RDV
// (adresse, temps de trajet, à apporter, infos pratiques). Uses shared primitives.

Object.assign(NB_ICONS, {
  car: 'M5 11l1.4-4.2A2 2 0 0 1 8.3 5.4h7.4a2 2 0 0 1 1.9 1.4L19 11M5 11h14a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1ZM7.5 14h.01M16.5 14h.01',
  bus: 'M6 5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v10a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V5ZM6 11h12M8.5 20l1-2M15.5 20l-1-2M9.5 16h.01M14.5 16h.01',
  walk: 'M13.5 6a1.4 1.4 0 1 0 0-.01M12 9.5l2.6 1.4.6 3.4M12 9.5 9.8 12.5M14.6 14.3 16 20M9.8 12.5 8 14.5 7 20',
  bag: 'M6 8h12l-1 11.5a1 1 0 0 1-1 .9H8a1 1 0 0 1-1-.9L6 8ZM9 8V6.2a3 3 0 0 1 6 0V8',
  creditCard: 'M3 7h18a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1ZM2 11h20',
  users: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM2 20a7 7 0 0 1 14 0M16.5 4.3a3.5 3.5 0 0 1 0 6.9M22 20a7 7 0 0 0-4.5-6.5',
  clipboard: 'M9 4h6v3H9V4ZM9 5H6a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1h-3',
  logout: 'M14 4h4a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-4M10 16l-4-4 4-4M6 12h11',
});

// editable field (looks tappable, with edit affordance)
function EditField({ label, value, hint }) {
  return (
    <label style={{ display: 'block', marginBottom: 14 }}>
      <span className="t-label" style={{ color: 'var(--text-secondary)', display: 'block', marginBottom: 6 }}>{label}</span>
      <div style={{ height: 48, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', border: '1px solid var(--border-default)', display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px' }}>
        <span className="t-body-lg" style={{ flex: 1, color: value ? 'var(--text-primary)' : 'var(--text-tertiary)' }}>{value || hint}</span>
        <span style={{ color: 'var(--text-tertiary)' }}><Icon name="edit" size={16} stroke={2} /></span>
      </div>
    </label>
  );
}

// ── Couverture santé — modifier (AME / CMU-CSS / mutuelle / carte) ──
function ScreenCouverture({ dark }) {
  const regimes = [
    { l: 'Régime général', d: 'Assurance Maladie', on: true },
    { l: 'AME', d: "Aide médicale d'État" },
    { l: 'Complémentaire santé solidaire', d: 'CSS · ex-CMU-C' },
  ];
  return (
    <Screen dark={dark}>
      <NavTop title="Couverture santé" />
      <Scroll style={{ padding: '0 20px' }}>
        <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '4px 0 8px' }}>Régime obligatoire</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 20 }}>
          {regimes.map((r, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', borderRadius: 'var(--r-md)',
              background: r.on ? 'var(--primary-subtle-bg)' : 'var(--bg-surface)', border: '1px solid ' + (r.on ? 'var(--primary)' : 'var(--border-subtle)') }}>
              <span style={{ width: 20, height: 20, borderRadius: '50%', flexShrink: 0, border: '2px solid ' + (r.on ? 'var(--primary)' : 'var(--border-strong)'),
                display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{r.on && <span style={{ width: 10, height: 10, borderRadius: '50%', background: 'var(--primary)' }} />}</span>
              <div style={{ flex: 1 }}>
                <div className="t-label" style={{ color: 'var(--text-primary)' }}>{r.l}</div>
                <div className="t-micro" style={{ color: 'var(--text-tertiary)', fontWeight: 400 }}>{r.d}</div>
              </div>
            </div>
          ))}
        </div>
        <EditField label="N° de sécurité sociale" value="2 91 03 69 123 456 78" />

        <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '8px 0 8px' }}>Complémentaire (mutuelle)</div>
        <EditField label="Mutuelle" value="MGEN" />
        <EditField label="N° d'adhérent" value="1 234 567" />
        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Carte de mutuelle</div>
        <div style={{ display: 'flex', gap: 10, marginBottom: 14 }}>
          {['Recto', 'Verso'].map((s, i) => (
            <div key={i} style={{ flex: 1, height: 96, borderRadius: 'var(--r-lg)', border: '1.5px dashed var(--border-strong)', background: 'var(--bg-surface)',
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6, color: 'var(--text-tertiary)' }}>
              <Icon name="camera" size={22} stroke={2} /><span className="t-micro">{s} · ajouter</span>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 14px', borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', marginBottom: 8 }}>
          <span style={{ color: 'var(--primary)' }}><Icon name="check" size={18} stroke={2} /></span>
          <span className="t-label" style={{ flex: 1, color: 'var(--text-primary)' }}>Tiers payant activé</span>
          <span style={{ width: 40, height: 24, borderRadius: 999, background: 'var(--primary)', position: 'relative' }}><span style={{ position: 'absolute', top: 2, right: 2, width: 20, height: 20, borderRadius: '50%', background: '#fff' }} /></span>
        </div>
        <div style={{ height: 8 }} />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full icon="check">Enregistrer</Button>
      </div>
    </Screen>
  );
}

// ── Mes proches / enfants — gérer ──
function ScreenProches({ dark }) {
  const proches = [
    { name: 'Léo Rousseau', init: 'LR', rel: 'Enfant · 8 ans', cov: 'Ayant droit' },
    { name: 'Jade Rousseau', init: 'JR', rel: 'Enfant · 5 ans', cov: 'Ayant droit', tone: 'sand' },
  ];
  return (
    <Screen dark={dark}>
      <NavTop title="Mes proches" />
      <Scroll style={{ padding: '0 20px' }}>
        <p className="t-body" style={{ color: 'var(--text-secondary)', margin: '4px 0 16px', textWrap: 'pretty' }}>
          Gérez les comptes des personnes dont vous avez la charge. Chaque proche a sa propre couverture (Carte Vitale, AME, mutuelle).
        </p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {proches.map((p, i) => (
            <Card key={i} pad={14} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <Avatar initials={p.init} size={46} tone={p.tone || 'brand'} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600, fontSize: 16 }}>{p.name}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 3 }}>
                  <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{p.rel}</span>
                  <Badge tone="neutral">{p.cov}</Badge>
                </div>
              </div>
              <span style={{ color: 'var(--text-tertiary)' }}><Icon name="chevronR" size={18} stroke={2} /></span>
            </Card>
          ))}
        </div>
        <button style={{ width: '100%', marginTop: 14, height: 52, borderRadius: 'var(--r-lg)', border: '1.5px dashed var(--border-strong)', background: 'transparent',
          color: 'var(--primary)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, font: '600 15px/1 var(--font-ui)' }}>
          <Icon name="plus" size={18} stroke={2.4} />Ajouter un proche
        </button>
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

Object.assign(window, { ScreenRechercheRDV, ScreenPreparationRDV, EditField, ScreenCouverture, ScreenProches });

// ── Recherche de RDV (disponibilités, slot-centré) ──
function ScreenRechercheRDV({ dark }) {
  const days = [{ d: 'Auj.', n: '3', on: true }, { d: 'Mer.', n: '4' }, { d: 'Jeu.', n: '5' }, { d: 'Ven.', n: '6' }, { d: 'Sam.', n: '7' }, { d: 'Lun.', n: '9' }];
  const res = [
    { name: 'Dr Claire Lefèvre', init: 'CL', spec: 'Chirurgien-dentiste', dist: '1,2 km', tone: 'brand', first: "Aujourd'hui", slots: ['14:30', '15:00', '16:15'] },
    { name: 'Centre dentaire Part-Dieu', init: 'PD', spec: 'Cabinet · 4 praticiens', dist: '2,1 km', tone: 'neutral', first: "Aujourd'hui", slots: ['15:45', '16:30', '17:00'] },
    { name: 'Dr Hugo Marin', init: 'HM', spec: 'Dentiste · Implantologie', dist: '2,4 km', tone: 'sand', first: 'Jeudi', slots: ['Jeu. 09:00', 'Jeu. 11:30'] },
  ];
  return (
    <Screen dark={dark}>
      <NavTop title="Trouver un rendez-vous" trailing={<IconButton name="map" />} />
      <div style={{ padding: '0 20px', flexShrink: 0 }}>
        <div style={{ height: 48, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)', border: '1px solid var(--border-default)',
          display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px', color: 'var(--text-tertiary)', marginBottom: 10 }}>
          <Icon name="search" size={20} stroke={2} /><span className="t-body">Dentiste · détartrage</span>
        </div>
        <div style={{ display: 'flex', gap: 8, marginBottom: 12, overflowX: 'auto' }}>
          <Chip icon="mapPin" active>Lyon · 5 km</Chip>
          <Chip icon="video">Téléconsult</Chip>
          <Chip icon="sliders">Filtres</Chip>
        </div>
        {/* day strip */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 4, overflowX: 'auto', paddingBottom: 4 }}>
          {days.map((day, i) => (
            <div key={i} style={{ minWidth: 52, flexShrink: 0, textAlign: 'center', padding: '8px 0', borderRadius: 'var(--r-md)',
              background: day.on ? 'var(--primary)' : 'var(--bg-surface)', color: day.on ? 'var(--text-on-primary)' : 'var(--text-secondary)',
              border: '1px solid ' + (day.on ? 'transparent' : 'var(--border-subtle)') }}>
              <div className="t-micro" style={{ opacity: 0.85 }}>{day.d}</div>
              <div style={{ font: '600 17px/1.2 var(--font-ui)' }}>{day.n}</div>
            </div>
          ))}
        </div>
      </div>
      <Scroll style={{ padding: '12px 20px 8px' }}>
        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 12 }}>12 praticiens · triés par 1re dispo</div>
        {res.map((p, i) => (
          <Card key={i} pad={14} style={{ marginBottom: 12 }}>
            <div style={{ display: 'flex', gap: 12 }}>
              <Avatar initials={p.init} size={48} tone={p.tone} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>{p.name}</div>
                <div className="t-caption" style={{ color: 'var(--text-secondary)' }}>{p.spec}</div>
                <div style={{ display: 'flex', gap: 8, marginTop: 5, alignItems: 'center' }}>
                  <Badge tone="success" icon="clock">1re dispo · {p.first}</Badge>
                  <span className="t-caption" style={{ color: 'var(--text-tertiary)', display: 'inline-flex', alignItems: 'center', gap: 3 }}><Icon name="mapPin" size={13} stroke={2} />{p.dist}</span>
                </div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              {p.slots.map((s, j) => (
                <span key={j} style={{ flex: 1, textAlign: 'center', padding: '9px 4px', borderRadius: 'var(--r-sm)', font: '600 13px/1.2 var(--font-ui)',
                  background: j === 0 ? 'var(--primary-subtle-bg)' : 'var(--bg-page)', color: j === 0 ? 'var(--primary-subtle-fg)' : 'var(--text-secondary)',
                  border: '1px solid ' + (j === 0 ? 'transparent' : 'var(--border-subtle)') }}>{s}</span>
              ))}
            </div>
          </Card>
        ))}
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

// ── Préparation du RDV (adresse, trajet, à apporter, infos pratiques) ──
function ScreenPreparationRDV({ dark }) {
  const modes = [{ icon: 'car', l: 'Voiture', t: '12 min' }, { icon: 'bus', l: 'Transports', t: '18 min' }, { icon: 'walk', l: 'À pied', t: '32 min' }];
  const apporter = [{ t: 'Carte Vitale', on: true }, { t: 'Carte de mutuelle', on: true }, { t: 'Ordonnances en cours', on: false }, { t: 'Radios récentes', on: false }];
  return (
    <Screen dark={dark}>
      <NavTop title="Préparer mon RDV" />
      <Scroll style={{ padding: '0 20px' }}>
        {/* summary */}
        <Card pad={16} style={{ marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <Avatar initials="CL" size={44} tone="brand" />
            <div style={{ flex: 1 }}>
              <div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>Dr Claire Lefèvre</div>
              <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Première consultation</div>
            </div>
            <Badge tone="success" icon="check">Confirmé</Badge>
          </div>
          <div style={{ display: 'flex', gap: 16, marginTop: 12, paddingTop: 12, borderTop: '1px solid var(--border-subtle)' }}>
            <span className="t-label" style={{ color: 'var(--text-primary)', display: 'inline-flex', alignItems: 'center', gap: 6 }}><Icon name="calendar" size={16} stroke={2} />Mar. 3 juin · 14:30</span>
          </div>
        </Card>

        {/* map + address */}
        <Placeholder label="plan · accès & itinéraire" height={130} />
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, margin: '12px 0' }}>
          <span style={{ color: 'var(--text-tertiary)', marginTop: 1 }}><Icon name="mapPin" size={18} stroke={2} /></span>
          <div style={{ flex: 1 }}>
            <div className="t-body" style={{ color: 'var(--text-primary)' }}>12 rue de la République</div>
            <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>69002 Lyon · 2e étage, porte droite</div>
          </div>
          <span className="t-label" style={{ color: 'var(--primary)', display: 'inline-flex', alignItems: 'center', gap: 4 }}><Icon name="navigation" size={15} stroke={2} />Itinéraire</span>
        </div>

        {/* travel modes */}
        <div style={{ display: 'flex', gap: 10, marginBottom: 18 }}>
          {modes.map((m, i) => (
            <div key={i} style={{ flex: 1, padding: '12px 8px', borderRadius: 'var(--r-lg)', background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', textAlign: 'center' }}>
              <span style={{ color: 'var(--primary)' }}><Icon name={m.icon} size={22} stroke={2} /></span>
              <div className="t-label tabular" style={{ color: 'var(--text-primary)', marginTop: 6 }}>{m.t}</div>
              <div className="t-micro" style={{ color: 'var(--text-tertiary)', fontWeight: 400 }}>{m.l}</div>
            </div>
          ))}
        </div>

        {/* à apporter */}
        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8, display: 'flex', alignItems: 'center', gap: 7 }}><Icon name="bag" size={16} stroke={2} />À apporter</div>
        <Card pad={16} style={{ padding: '4px 16px', marginBottom: 18 }}>
          {apporter.map((a, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 0', borderBottom: i < apporter.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
              <span style={{ width: 22, height: 22, borderRadius: 6, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: a.on ? 'var(--primary)' : 'transparent', border: a.on ? 'none' : '2px solid var(--border-strong)', color: 'var(--text-on-primary)' }}>
                {a.on && <Icon name="check" size={14} stroke={3} />}</span>
              <span className="t-body" style={{ color: 'var(--text-primary)' }}>{a.t}</span>
            </div>
          ))}
        </Card>

        {/* infos pratiques */}
        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>Infos pratiques</div>
        <Card pad={16} style={{ padding: '2px 16px' }}>
          <InfoRow icon="lock">Code d'entrée : <b style={{ color: 'var(--text-primary)' }}>24B7</b></InfoRow>
          <div style={{ height: 1, background: 'var(--border-subtle)' }} />
          <InfoRow icon="car">Parking Vinci République à 50 m</InfoRow>
          <div style={{ height: 1, background: 'var(--border-subtle)' }} />
          <InfoRow icon="info">Accès PMR · ascenseur disponible</InfoRow>
        </Card>
        <div style={{ display: 'flex', gap: 9, alignItems: 'center', margin: '14px 2px' }}>
          <span style={{ color: 'var(--primary)' }}><Icon name="bell" size={16} stroke={2} /></span>
          <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Rappel automatique 1 h avant le rendez-vous.</span>
        </div>
        <div style={{ height: 8 }} />
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Button variant="primary" full icon="qr">Préparer mon check-in</Button>
        <Button variant="ghost" full icon="phone">Appeler le cabinet</Button>
      </div>
    </Screen>
  );
}

Object.assign(window, { ScreenRechercheRDV, ScreenPreparationRDV });
