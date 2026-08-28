// Nubia screens — group 1: Accueil/Rechercher + Profil praticien & réservation

// ─────────────────────────────────────────────────────────────
// Provider result card (used on Accueil)
// ─────────────────────────────────────────────────────────────
function ProviderCard({ p }) {
  return (
    <Card pad={14} style={{ marginBottom: 12 }}>
      <div style={{ display: 'flex', gap: 12 }}>
        <Avatar initials={p.initials} size={52} tone={p.tone || 'brand'} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>{p.name}</span>
            {p.verified && <Icon name="shield" size={16} stroke={2.2} style={{ color: 'var(--primary)' }} />}
          </div>
          <div className="t-caption" style={{ color: 'var(--text-secondary)' }}>{p.specialty}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 5 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: 'var(--accent-700)' }} className="t-caption">
              <Icon name="star" size={13} fill={true} />{p.rating}
            </span>
            <span className="t-caption" style={{ color: 'var(--text-tertiary)', display: 'inline-flex', alignItems: 'center', gap: 3 }}>
              <Icon name="mapPin" size={13} stroke={2} />{p.distance}
            </span>
            <Badge tone="neutral">{p.secteur}</Badge>
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
        {p.slots.map((s, i) => (
          <span key={i} style={{
            flex: 1, textAlign: 'center', padding: '8px 4px', borderRadius: 'var(--r-sm)',
            background: i === 0 ? 'var(--primary-subtle-bg)' : 'var(--bg-page)',
            color: i === 0 ? 'var(--primary-subtle-fg)' : 'var(--text-secondary)',
            border: '1px solid ' + (i === 0 ? 'transparent' : 'var(--border-subtle)'),
            font: '600 13px/1.2 var(--font-ui)',
          }}>{s}</span>
        ))}
      </div>
    </Card>
  );
}

function ScreenAccueil({ dark }) {
  const providers = [
    { name: 'Dr Claire Lefèvre', specialty: 'Chirurgien-dentiste', initials: 'CL', verified: true,
      rating: '4,9', distance: '1,2 km', secteur: 'Secteur 1', slots: ['Auj. 14:30', 'Dem. 09:00', 'Jeu. 11:15'] },
    { name: 'Dr Hugo Marin', specialty: 'Dentiste · Implantologie', initials: 'HM', verified: true, tone: 'sand',
      rating: '4,8', distance: '2,4 km', secteur: 'Secteur 2', slots: ['Jeu. 16:00', 'Ven. 10:30', 'Lun. 08:45'] },
  ];
  const specialties = ['Dentiste', 'Ophtalmologue', 'Dermatologue', 'Kiné', 'Généraliste'];
  return (
    <Screen dark={dark} nav="home">
      <Header sub="Bonjour" title="Camille" display
        trailing={<IconButton name="bell" badge />} />

      {/* mini-dashboard — actions à réaliser */}
      <div style={{ padding: '4px 20px 0', display: 'flex', gap: 8, flexShrink: 0 }}>
        {[
          { icon: 'calendar', v: 'Mar. 3', l: 'Prochain RDV', tone: 'brand' },
          { icon: 'document', v: '1', l: 'À signer', tone: 'warning' },
          { icon: 'euro', v: '250 €', l: 'À régler', tone: 'danger' },
        ].map((t, i) => {
          const alert = t.tone !== 'brand';
          return (
            <div key={i} style={{
              flex: 1, padding: '11px 12px', borderRadius: 'var(--r-lg)',
              background: 'var(--bg-surface)', border: '1px solid ' + (alert ? `var(--${t.tone}-bg)` : 'var(--border-subtle)'),
              boxShadow: 'var(--shadow-sm)',
            }}>
              <div style={{ color: alert ? `var(--${t.tone}-fg)` : 'var(--primary)', marginBottom: 7 }}>
                <Icon name={t.icon} size={18} stroke={2} />
              </div>
              <div className="t-h3 tabular" style={{ color: 'var(--text-primary)', fontSize: 18, lineHeight: '22px' }}>{t.v}</div>
              <div className="t-micro" style={{ color: 'var(--text-tertiary)', fontWeight: 500 }}>{t.l}</div>
            </div>
          );
        })}
      </div>

      <Scroll style={{ padding: '16px 20px 8px' }}>
        {/* search */}
        <div style={{
          height: 52, borderRadius: 'var(--r-md)', background: 'var(--bg-surface)',
          border: '1px solid var(--border-default)', display: 'flex', alignItems: 'center',
          gap: 10, padding: '0 14px', color: 'var(--text-tertiary)', boxShadow: 'var(--shadow-sm)',
        }}>
          <Icon name="search" size={20} stroke={2} />
          <span className="t-body-lg">Praticien, spécialité, besoin…</span>
        </div>
        <div style={{ display: 'flex', gap: 8, margin: '12px 0 4px' }}>
          <Chip icon="mapPin" active>Autour de moi · Lyon</Chip>
          <Chip icon="sliders">Filtres</Chip>
        </div>

        <div className="t-label" style={{ color: 'var(--text-secondary)', margin: '18px 0 10px' }}>Spécialités</div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {specialties.map((s, i) => <Chip key={i} active={i === 0}>{s}</Chip>)}
        </div>

        {/* results header */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', margin: '24px 0 12px' }}>
          <span className="t-label" style={{ color: 'var(--text-secondary)' }}>24 résultats près de vous</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: 'var(--primary)' }} className="t-label">
            <Icon name="map" size={16} stroke={2} />Carte
          </span>
        </div>
        {providers.map((p, i) => <ProviderCard key={i} p={p} />)}
      </Scroll>
    </Screen>
  );
}

// ─────────────────────────────────────────────────────────────
// Profil praticien & réservation
// ─────────────────────────────────────────────────────────────
function InfoRow({ icon, children }) {
  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '10px 0' }}>
      <span style={{ color: 'var(--text-tertiary)', marginTop: 1 }}><Icon name={icon} size={18} stroke={2} /></span>
      <div className="t-body" style={{ color: 'var(--text-secondary)', flex: 1 }}>{children}</div>
    </div>
  );
}

function ScreenProfilPraticien({ dark }) {
  const days = [
    { d: 'Mar.', n: '3 juin', slots: ['14:30', '15:00', '16:15'] },
    { d: 'Mer.', n: '4 juin', slots: ['09:00', '11:30'] },
    { d: 'Jeu.', n: '5 juin', slots: ['08:45', '10:00', '14:00'] },
  ];
  return (
    <Screen dark={dark}>
      {/* compact top bar with back */}
      <div style={{ padding: '54px 16px 8px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
        <IconButton name="chevronL" />
        <div style={{ display: 'flex', gap: 8 }}>
          <IconButton name="heart" />
        </div>
      </div>

      <Scroll style={{ padding: '0 20px' }}>
        {/* identity */}
        <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
          <Avatar initials="CL" size={64} tone="brand" />
          <div style={{ flex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span className="t-h2" style={{ color: 'var(--text-primary)' }}>Dr Claire Lefèvre</span>
            </div>
            <div className="t-body" style={{ color: 'var(--text-secondary)' }}>Chirurgien-dentiste</div>
            <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              <Badge tone="brand" icon="shield">RPPS vérifié</Badge>
              <Badge tone="neutral">Secteur 1</Badge>
            </div>
          </div>
        </div>

        {/* rating strip */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '16px 0', padding: '12px 14px',
          background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--r-lg)' }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, color: 'var(--accent-700)', fontWeight: 600 }} className="t-title">
            <Icon name="star" size={18} fill={true} />4,9
          </span>
          <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>· 182 avis vérifiés</span>
        </div>

        {/* address + mini map */}
        <Placeholder label="plan · 12 rue de la République, Lyon" height={120} />
        <div style={{ paddingTop: 4 }}>
          <InfoRow icon="mapPin">12 rue de la République, 69002 Lyon <span style={{ color: 'var(--primary)', fontWeight: 500 }}>· Itinéraire</span></InfoRow>
          <div style={{ height: 1, background: 'var(--border-subtle)' }} />
          <InfoRow icon="euro">Conventionné secteur 1 · Carte Vitale acceptée</InfoRow>
          <div style={{ height: 1, background: 'var(--border-subtle)' }} />
          <InfoRow icon="info">Langues : français, anglais · Accès PMR</InfoRow>
        </div>

        {/* disponibilités */}
        <div className="t-h3" style={{ color: 'var(--text-primary)', margin: '20px 0 12px' }}>Prochaines disponibilités</div>
        <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 4 }}>
          {days.map((day, i) => (
            <div key={i} style={{ minWidth: 96, flexShrink: 0 }}>
              <div style={{ textAlign: 'center', marginBottom: 8 }}>
                <div className="t-label" style={{ color: 'var(--text-primary)' }}>{day.d}</div>
                <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>{day.n}</div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {day.slots.map((s, j) => (
                  <span key={j} style={{
                    textAlign: 'center', padding: '9px 0', borderRadius: 'var(--r-sm)',
                    background: i === 0 && j === 0 ? 'var(--primary)' : 'var(--primary-subtle-bg)',
                    color: i === 0 && j === 0 ? 'var(--text-on-primary)' : 'var(--primary-subtle-fg)',
                    font: '600 14px/1 var(--font-ui)', cursor: 'pointer',
                  }}>{s}</span>
                ))}
              </div>
            </div>
          ))}
        </div>

        {/* présentation */}
        <div className="t-h3" style={{ color: 'var(--text-primary)', margin: '22px 0 8px' }}>Présentation</div>
        <p className="t-body" style={{ color: 'var(--text-secondary)', margin: 0, textWrap: 'pretty' }}>
          Diplômée de la faculté de Lyon, le Dr Lefèvre exerce la dentisterie générale et l'implantologie depuis 12 ans…
          <span style={{ color: 'var(--primary)', fontWeight: 500 }}> Voir plus</span>
        </p>
        <div style={{ height: 16 }} />
      </Scroll>

      {/* sticky CTA */}
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full iconRight="arrowR">Prendre rendez-vous</Button>
      </div>
    </Screen>
  );
}

Object.assign(window, { ProviderCard, ScreenAccueil, InfoRow, ScreenProfilPraticien });
