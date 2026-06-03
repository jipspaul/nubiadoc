// Nubia — THE WEDGE (devis → signature → acompte). Hero screen, 3 variations.
// Shared demo data
const WEDGE = {
  praticien: 'Dr Claire Lefèvre',
  titre: 'Plan de soins implantaire',
  lignes: [
    { acte: 'Consultation & bilan radio', montant: '50 €' },
    { acte: 'Implant titane (dent 26)', montant: '1 200 €' },
    { acte: 'Pilier + couronne céramique', montant: '750 €' },
    { acte: 'Détartrage complet', montant: '60 €' },
  ],
  total: '2 060 €',
  rembourse: '− 510 €',
  reste: '1 550 €',
  acompte: '465 €',
};

function WedgeLines({ compact }) {
  return (
    <div>
      {WEDGE.lignes.map((l, i) => (
        <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
          padding: compact ? '8px 0' : '11px 0', borderBottom: i < WEDGE.lignes.length - 1 ? '1px solid var(--border-subtle)' : 'none' }}>
          <span className="t-body" style={{ color: 'var(--text-secondary)' }}>{l.acte}</span>
          <span className="t-body tabular" style={{ color: 'var(--text-primary)', fontWeight: 500 }}>{l.montant}</span>
        </div>
      ))}
    </div>
  );
}

function Reassurance() {
  return (
    <div style={{ display: 'flex', gap: 9, alignItems: 'center', padding: '12px 2px' }}>
      <span style={{ color: 'var(--primary)' }}><Icon name="lock" size={17} stroke={2} /></span>
      <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>
        Signature électronique sécurisée <b style={{ color: 'var(--text-secondary)' }}>(eIDAS)</b> · devis chiffré &amp; horodaté
      </span>
    </div>
  );
}

function WedgeTopBar({ dark }) {
  return (
    <div style={{ padding: '52px 16px 10px', display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
      <IconButton name="chevronL" />
      <span className="t-title" style={{ flex: 1, textAlign: 'center', color: 'var(--text-primary)', fontWeight: 600 }}>Devis</span>
      <div style={{ width: 44 }} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// A — Sobre & clair (by-the-book, spec C)
// ─────────────────────────────────────────────────────────────
function ScreenWedgeA({ dark }) {
  return (
    <Screen dark={dark}>
      <WedgeTopBar />
      <Scroll style={{ padding: '0 20px' }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 14 }}>
          <Badge tone="warning" icon="clock">À signer</Badge>
        </div>

        {/* amount header */}
        <div style={{ textAlign: 'center', marginBottom: 16 }}>
          <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Total du plan de soins</div>
          <div className="t-display tabular" style={{ fontSize: 44, lineHeight: '52px', color: 'var(--text-primary)' }}>{WEDGE.total}</div>
          <div className="t-caption" style={{ color: 'var(--text-secondary)' }}>{WEDGE.titre} · {WEDGE.praticien}</div>
        </div>

        {/* reste à charge bandeau */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 16px',
          borderRadius: 'var(--r-lg)', background: 'var(--primary-subtle-bg)', marginBottom: 18 }}>
          <div>
            <div className="t-label" style={{ color: 'var(--primary-subtle-fg)' }}>Reste à charge</div>
            <div className="t-micro" style={{ color: 'var(--primary-subtle-fg)', opacity: 0.8, fontWeight: 400 }}>après remboursements</div>
          </div>
          <div className="t-h2 tabular" style={{ color: 'var(--primary-subtle-fg)' }}>{WEDGE.reste}</div>
        </div>

        <Card pad={16}>
          <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 4 }}>Détail des actes</div>
          <WedgeLines />
        </Card>
        <Reassurance />
        <div style={{ height: 8 }} />
      </Scroll>

      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)',
        display: 'flex', flexDirection: 'column', gap: 8 }}>
        <Button variant="primary" full icon="edit">Signer le devis</Button>
        <Button variant="ghost" full>Poser une question au cabinet</Button>
      </div>
    </Screen>
  );
}

// ─────────────────────────────────────────────────────────────
// B — Premium sable (editorial gold-sand header; sand decorative only)
// ─────────────────────────────────────────────────────────────
function ScreenWedgeB({ dark }) {
  return (
    <Screen dark={dark}>
      {/* sand hero band */}
      <div style={{ background: 'var(--accent-100)', flexShrink: 0, paddingBottom: 22 }}>
        <div style={{ padding: '52px 16px 6px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ color: 'var(--accent-700)' }}><Icon name="chevronL" size={22} stroke={2} /></span>
          <span className="t-label" style={{ flex: 1, color: 'var(--accent-700)' }}>Devis</span>
          <Badge tone="sand" icon="clock">À signer</Badge>
        </div>
        <div style={{ padding: '14px 28px 0', textAlign: 'center' }}>
          <div style={{ font: '500 12px/1 var(--font-ui)', letterSpacing: 2, textTransform: 'uppercase', color: 'var(--accent-700)', marginBottom: 10 }}>
            Plan de soins
          </div>
          <div className="tabular" style={{ font: '600 52px/1 var(--font-display)', color: 'var(--n-900)', letterSpacing: -1 }}>{WEDGE.total}</div>
          <div className="t-caption" style={{ color: 'var(--accent-700)', marginTop: 10 }}>{WEDGE.praticien} · soins implantaires</div>
        </div>
      </div>

      <Scroll style={{ padding: '20px 20px 0' }}>
        <WedgeLines compact />
        <div style={{ height: 1, background: 'var(--border-default)', margin: '4px 0 14px' }} />
        {/* reste à charge — elegant */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
          <span className="t-caption" style={{ color: 'var(--text-tertiary)' }}>Pris en charge (Sécu + mutuelle)</span>
          <span className="t-body tabular" style={{ color: 'var(--success-fg)', fontWeight: 500 }}>{WEDGE.rembourse}</span>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>Reste à charge</span>
          <span className="tabular" style={{ font: '600 26px/1 var(--font-display)', color: 'var(--primary)', whiteSpace: 'nowrap', flexShrink: 0 }}>{WEDGE.reste}</span>
        </div>
        <Reassurance />
      </Scroll>

      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full icon="edit">Signer le devis</Button>
      </div>
    </Screen>
  );
}

// ─────────────────────────────────────────────────────────────
// C — Reste-à-charge d'abord + micro-UX paiement (stepper, acompte, Apple Pay)
// ─────────────────────────────────────────────────────────────
function WedgeStepper({ step = 0 }) {
  const steps = ['Signer', 'Payer', 'Reçu'];
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 4px' }}>
      {steps.map((s, i) => (
        <React.Fragment key={i}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
            <span style={{ width: 22, height: 22, borderRadius: '50%', flexShrink: 0,
              background: i <= step ? 'var(--primary)' : 'var(--border-subtle)',
              color: i <= step ? 'var(--text-on-primary)' : 'var(--text-tertiary)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', font: '600 12px/1 var(--font-ui)' }}>
              {i < step ? <Icon name="check" size={12} stroke={3} /> : i + 1}
            </span>
            <span className="t-caption" style={{ color: i <= step ? 'var(--text-primary)' : 'var(--text-tertiary)', fontWeight: i === step ? 600 : 400 }}>{s}</span>
          </div>
          {i < steps.length - 1 && <div style={{ flex: 1, height: 2, background: 'var(--border-subtle)' }} />}
        </React.Fragment>
      ))}
    </div>
  );
}

function ScreenWedgeC({ dark }) {
  return (
    <Screen dark={dark}>
      <WedgeTopBar />
      <div style={{ padding: '0 20px 16px', flexShrink: 0 }}>
        <WedgeStepper step={0} />
      </div>
      <Scroll style={{ padding: '0 20px' }}>
        {/* reste à charge hero */}
        <div style={{ padding: '20px', borderRadius: 'var(--r-xl)', background: 'var(--primary)', color: 'var(--text-on-primary)', marginBottom: 14 }}>
          <div className="t-caption" style={{ opacity: 0.85 }}>Votre reste à charge</div>
          <div className="t-display tabular" style={{ fontSize: 46, lineHeight: '54px', color: 'var(--text-on-primary)', margin: '2px 0 12px' }}>{WEDGE.reste}</div>
          <div style={{ display: 'flex', justifyContent: 'space-between', font: '500 13px/1.6 var(--font-ui)' }}>
            <span style={{ opacity: 0.85 }}>Total des soins</span><span className="tabular">{WEDGE.total}</span>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', font: '500 13px/1.6 var(--font-ui)' }}>
            <span style={{ opacity: 0.85 }}>Remboursements</span><span className="tabular">{WEDGE.rembourse}</span>
          </div>
        </div>

        {/* acompte today */}
        <Card pad={16} style={{ marginBottom: 12, display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ width: 42, height: 42, borderRadius: 'var(--r-md)', background: 'var(--primary-subtle-bg)',
            color: 'var(--primary-subtle-fg)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <Icon name="euro" size={22} stroke={2} />
          </div>
          <div style={{ flex: 1 }}>
            <div className="t-label" style={{ color: 'var(--text-primary)' }}>Acompte aujourd'hui</div>
            <div className="t-caption" style={{ color: 'var(--text-tertiary)' }}>30 % · solde à la pose</div>
          </div>
          <div className="t-h3 tabular" style={{ color: 'var(--text-primary)' }}>{WEDGE.acompte}</div>
        </Card>

        {/* financement option */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 14px', borderRadius: 'var(--r-lg)',
          border: '1px dashed var(--border-default)', marginBottom: 14 }}>
          <span style={{ color: 'var(--text-secondary)' }}><Icon name="refresh" size={18} stroke={2} /></span>
          <span className="t-caption" style={{ color: 'var(--text-secondary)', flex: 1 }}>Possibilité de payer en <b style={{ color: 'var(--text-primary)' }}>3× sans frais</b></span>
          <span style={{ color: 'var(--text-tertiary)' }}><Icon name="chevronR" size={16} stroke={2} /></span>
        </div>

        {/* payment method preview (next step) */}
        <div className="t-label" style={{ color: 'var(--text-tertiary)', marginBottom: 8 }}>Moyen de paiement</div>
        <div style={{ display: 'flex', gap: 10, opacity: 0.55 }}>
          <div style={{ flex: 1, height: 46, borderRadius: 'var(--r-md)', background: 'var(--text-primary)', color: 'var(--bg-surface)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, font: '600 15px/1 var(--font-ui)' }}>
            <Icon name="checkCircle" size={17} stroke={2} />Apple&nbsp;Pay</div>
          <div style={{ flex: 1, height: 46, borderRadius: 'var(--r-md)', border: '1px solid var(--border-default)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, color: 'var(--text-secondary)' }}>
            <Icon name="document" size={17} stroke={2} /><span className="t-label">Carte</span>
          </div>
        </div>
        <div style={{ height: 8 }} />
      </Scroll>

      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full iconRight="arrowR">Signer et régler l'acompte</Button>
      </div>
    </Screen>
  );
}

Object.assign(window, {
  WEDGE, WedgeLines, Reassurance, WedgeTopBar,
  ScreenWedgeA, ScreenWedgeB, ScreenWedgeC, WedgeStepper,
});
