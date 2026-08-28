// Nubia screens — group 2: Mes RDV (+ salle d'attente, téléconsult), Messagerie, Documents

function Segmented({ options, active = 0 }) {
  return (
    <div style={{ display: 'flex', gap: 4, padding: 4, background: 'var(--bg-page)', borderRadius: 'var(--r-md)', border: '1px solid var(--border-subtle)' }}>
      {options.map((o, i) => (
        <span key={i} style={{
          flex: 1, textAlign: 'center', padding: '8px 0', borderRadius: 'var(--r-sm)',
          font: `${i === active ? 600 : 500} 14px/1 var(--font-ui)`,
          background: i === active ? 'var(--bg-surface)' : 'transparent',
          color: i === active ? 'var(--text-primary)' : 'var(--text-tertiary)',
          boxShadow: i === active ? 'var(--shadow-sm)' : 'none',
        }}>{o}</span>
      ))}
    </div>
  );
}

// ── RDV card ──
function RdvCard({ r }) {
  const today = r.when.startsWith('Aujourd');
  return (
    <Card pad={0} selected={today} style={{ marginBottom: 12, overflow: 'hidden' }}>
      <div style={{ padding: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 10 }}>
          <div style={{ display: 'flex', gap: 11, alignItems: 'center' }}>
            <Avatar initials={r.initials} size={44} tone={r.tele ? 'sand' : 'brand'} />
            <div>
              <div className="t-title" style={{ color: 'var(--text-primary)', fontWeight: 600 }}>{r.name}</div>
              <div className="t-caption" style={{ color: 'var(--text-secondary)' }}>{r.specialty}</div>
            </div>
          </div>
          <Badge tone={r.statusTone} icon={r.statusIcon}>{r.status}</Badge>
        </div>
        <div style={{ display: 'flex', gap: 16 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: today ? 'var(--primary)' : 'var(--text-secondary)' }} className="t-label">
            <Icon name="clock" size={16} stroke={2} />{r.when}
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--text-secondary)' }} className="t-caption">
            <Icon name={r.tele ? 'video' : 'mapPin'} size={16} stroke={2} />{r.place}
          </span>
        </div>
      </div>
      {today && (
        <div style={{ padding: '0 14px 14px' }}>
          <Button variant="primary" full icon="qr">Se présenter · Check-in</Button>
        </div>
      )}
    </Card>
  );
}

function ScreenMesRDV({ dark }) {
  const rdvs = [
    { name: 'Dr Claire Lefèvre', specialty: 'Chirurgien-dentiste', initials: 'CL', when: "Aujourd'hui · 14:30",
      place: '12 rue de la République', status: 'Confirmé', statusTone: 'success', statusIcon: 'check' },
    { name: 'Dr An Nguyen', specialty: 'Téléconsultation', initials: 'AN', when: 'Jeu. 5 juin · 18:00',
      place: 'Vidéo', status: 'Téléconsult', statusTone: 'info', statusIcon: 'video', tele: true },
    { name: 'Dr Hugo Marin', specialty: 'Implantologie', initials: 'HM', when: 'Mar. 17 juin · 09:15',
      place: '8 cours Lafayette', status: 'À confirmer', statusTone: 'warning', statusIcon: 'clock' },
  ];
  return (
    <Screen dark={dark} nav="rdv">
      <Header title="Mes rendez-vous" />
      <div style={{ padding: '4px 20px 14px', flexShrink: 0 }}>
        <Segmented options={['À venir', 'Historique']} active={0} />
      </div>
      <Scroll style={{ padding: '0 20px 8px' }}>
        {rdvs.map((r, i) => <RdvCard key={i} r={r} />)}
      </Scroll>
    </Screen>
  );
}

// ── Salle d'attente virtuelle ──
function ScreenSalleAttente({ dark }) {
  return (
    <Screen dark={dark}>
      <div style={{ padding: '54px 16px 8px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
        <IconButton name="chevronL" />
        <Badge tone="success" icon="check">Enregistré</Badge>
        <div style={{ width: 44 }} />
      </div>
      <Scroll style={{ padding: '8px 24px' }}>
        <div className="t-caption" style={{ color: 'var(--text-tertiary)', textAlign: 'center' }}>Salle d'attente · Dr Lefèvre</div>

        <div style={{ textAlign: 'center', margin: '36px 0 8px' }}>
          <div className="t-caption" style={{ color: 'var(--text-secondary)', marginBottom: 6 }}>Votre position dans la file</div>
          <div className="t-display tabular" style={{ fontSize: 80, lineHeight: '80px', color: 'var(--primary)' }}>2<span style={{ fontSize: 28, verticalAlign: 'super' }}>e</span></div>
          <div className="t-body-lg" style={{ color: 'var(--text-secondary)', marginTop: 6 }}>~ 10 min d'attente estimée</div>
        </div>

        {/* progress */}
        <div style={{ margin: '28px 0' }}>
          <div style={{ height: 8, borderRadius: 'var(--r-full)', background: 'var(--border-subtle)', overflow: 'hidden' }}>
            <div style={{ width: '62%', height: '100%', background: 'var(--primary)', borderRadius: 'var(--r-full)' }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8 }} className="t-micro">
            <span style={{ color: 'var(--text-tertiary)' }}>Enregistré 14:24</span>
            <span style={{ color: 'var(--text-tertiary)' }}>Votre tour</span>
          </div>
        </div>

        <Card style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <span style={{ color: 'var(--primary)' }}><Icon name="bell" size={22} stroke={2} /></span>
          <div className="t-caption" style={{ color: 'var(--text-secondary)', flex: 1 }}>
            Vous recevrez une notification <b style={{ color: 'var(--text-primary)' }}>5 minutes avant</b> votre passage. Restez à proximité.
          </div>
        </Card>

        <div style={{ marginTop: 12 }}>
          <Button variant="secondary" full icon="alert">Signaler un retard</Button>
        </div>
      </Scroll>
    </Screen>
  );
}

// ── Téléconsultation ──
function ScreenTeleconsult({ dark }) {
  return (
    <Screen dark={dark}>
      <Scroll style={{ display: 'flex', flexDirection: 'column' }}>
        {/* video stage */}
        <div style={{
          position: 'relative', margin: 16, marginTop: 58, borderRadius: 'var(--r-xl)', overflow: 'hidden',
          aspectRatio: '3/4',
          background: 'repeating-linear-gradient(135deg, var(--n-800) 0 12px, var(--n-900) 12px 24px)',
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14,
        }}>
          <Avatar initials="AN" size={72} tone="neutral" />
          <div style={{ textAlign: 'center', color: 'rgba(255,255,255,0.85)' }}>
            <div className="t-title" style={{ color: '#fff' }}>Dr An Nguyen</div>
            <div className="t-caption" style={{ color: 'rgba(255,255,255,0.6)' }}>En attente du praticien…</div>
          </div>
          {/* self view */}
          <div style={{ position: 'absolute', bottom: 14, right: 14, width: 84, height: 112, borderRadius: 'var(--r-md)',
            overflow: 'hidden', border: '2px solid rgba(255,255,255,0.5)' }}>
            <Placeholder label="vous" height={112} radius="0" style={{ border: 'none' }} />
          </div>
          <span style={{ position: 'absolute', top: 14, left: 14 }}>
            <Badge tone="info" icon="clock">Salle d'attente vidéo</Badge>
          </span>
        </div>

        <div style={{ padding: '0 20px' }}>
          {/* device test */}
          <div style={{ display: 'flex', gap: 10 }}>
            {[{ i: 'camera', l: 'Caméra OK' }, { i: 'mic', l: 'Micro OK' }].map((t, i) => (
              <div key={i} style={{ flex: 1, padding: '12px', borderRadius: 'var(--r-lg)', background: 'var(--bg-surface)',
                border: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', gap: 9 }}>
                <span style={{ color: 'var(--success-fg)' }}><Icon name={t.i} size={20} stroke={2} /></span>
                <span className="t-label" style={{ color: 'var(--text-primary)' }}>{t.l}</span>
                <span style={{ marginLeft: 'auto', color: 'var(--success-fg)' }}><Icon name="check" size={16} stroke={2.5} /></span>
              </div>
            ))}
          </div>
          <p className="t-caption" style={{ color: 'var(--text-tertiary)', textAlign: 'center', margin: '16px 0' }}>
            Le praticien démarrera l'appel à l'heure du rendez-vous.
          </p>
        </div>
      </Scroll>
      <div style={{ flexShrink: 0, padding: '12px 20px 30px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)' }}>
        <Button variant="primary" full icon="video">Rejoindre l'appel</Button>
      </div>
    </Screen>
  );
}

// ── Messagerie : liste ──
function ScreenMessagerie({ dark }) {
  const convos = [
    { name: 'Cabinet Lefèvre', initials: 'CL', msg: 'Votre ordonnance est disponible dans vos documents.', time: '11:02', unread: true, urgent: false },
    { name: 'Dr Hugo Marin', initials: 'HM', msg: 'Merci de nous envoyer une photo de la zone concernée.', time: 'Hier', unread: true, urgent: true, tone: 'sand' },
    { name: 'Centre dentaire Part-Dieu', initials: 'PD', msg: 'Votre RDV du 17 juin est confirmé.', time: 'Lun.', unread: false, urgent: false, tone: 'neutral' },
    { name: 'Dr An Nguyen', initials: 'AN', msg: "Bonjour, n'hésitez pas si vous avez des questions.", time: '28 mai', unread: false, urgent: false, tone: 'neutral' },
  ];
  return (
    <Screen dark={dark} nav="msg">
      <Header title="Messages" trailing={<IconButton name="edit" />} />
      <Scroll>
        {convos.map((c, i) => (
          <div key={i} style={{ display: 'flex', gap: 12, padding: '14px 20px', alignItems: 'center',
            borderBottom: '1px solid var(--border-subtle)', background: c.unread ? 'var(--bg-surface)' : 'transparent' }}>
            <Avatar initials={c.initials} size={48} tone={c.tone || 'brand'} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span className="t-title" style={{ fontWeight: c.unread ? 600 : 500, color: 'var(--text-primary)', fontSize: 16 }}>{c.name}</span>
                {c.urgent && <Badge tone="danger" icon="alert">Urgent</Badge>}
              </div>
              <div className="t-caption" style={{ color: c.unread ? 'var(--text-secondary)' : 'var(--text-tertiary)',
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontWeight: c.unread ? 500 : 400 }}>{c.msg}</div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
              <span className="t-micro" style={{ color: 'var(--text-tertiary)' }}>{c.time}</span>
              {c.unread && <span style={{ width: 9, height: 9, borderRadius: '50%', background: 'var(--primary)' }} />}
            </div>
          </div>
        ))}
      </Scroll>
    </Screen>
  );
}

// ── Conversation (fil) ──
function Bubble({ me, children, time }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: me ? 'flex-end' : 'flex-start', marginBottom: 10 }}>
      <div style={{
        maxWidth: '78%', padding: '10px 14px', borderRadius: 16,
        borderBottomRightRadius: me ? 4 : 16, borderBottomLeftRadius: me ? 16 : 4,
        background: me ? 'var(--primary)' : 'var(--bg-surface)',
        color: me ? 'var(--text-on-primary)' : 'var(--text-primary)',
        border: me ? 'none' : '1px solid var(--border-subtle)',
      }} className="t-body">{children}</div>
      <span className="t-micro" style={{ color: 'var(--text-tertiary)', margin: '4px 4px 0' }}>{time}</span>
    </div>
  );
}

function ScreenConversation({ dark }) {
  return (
    <Screen dark={dark}>
      <div style={{ padding: '52px 16px 10px', display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0,
        borderBottom: '1px solid var(--border-subtle)', background: 'var(--bg-surface)' }}>
        <IconButton name="chevronL" />
        <Avatar initials="HM" size={38} tone="sand" />
        <div style={{ flex: 1 }}>
          <div className="t-label" style={{ color: 'var(--text-primary)' }}>Dr Hugo Marin</div>
          <div className="t-micro" style={{ color: 'var(--text-tertiary)' }}>Implantologie</div>
        </div>
      </div>
      {/* urgent banner */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 16px', background: 'var(--danger-bg)', flexShrink: 0 }}>
        <span style={{ color: 'var(--danger-fg)' }}><Icon name="alert" size={16} stroke={2.2} /></span>
        <span className="t-caption" style={{ color: 'var(--danger-fg)', flex: 1 }}>Conversation marquée urgente · En cas d'urgence vitale, appelez le 15.</span>
      </div>
      <Scroll style={{ padding: '16px 16px 8px' }}>
        <div className="t-micro" style={{ textAlign: 'center', color: 'var(--text-tertiary)', marginBottom: 14 }}>Hier</div>
        <Bubble time="18:40">Bonjour, j'ai une douleur à la molaire en bas à droite depuis ce matin.</Bubble>
        <Bubble me time="18:42">Bonjour Camille. Merci de nous envoyer une photo de la zone concernée.</Bubble>
        <div style={{ display: 'flex', justifyContent: 'flex-start', marginBottom: 10 }}>
          <Placeholder label="photo · zone molaire" height={120} style={{ width: 180 }} />
        </div>
        <Bubble me time="18:51">Merci. Je vous propose un créneau demain à 9h, est-ce que cela vous convient&nbsp;?</Bubble>
      </Scroll>
      {/* input */}
      <div style={{ flexShrink: 0, padding: '10px 14px 28px', background: 'var(--bg-surface)', borderTop: '1px solid var(--border-subtle)',
        display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ color: 'var(--text-tertiary)' }}><Icon name="camera" size={24} stroke={2} /></span>
        <span style={{ color: 'var(--text-tertiary)' }}><Icon name="paperclip" size={22} stroke={2} /></span>
        <div style={{ flex: 1, height: 40, borderRadius: 'var(--r-full)', background: 'var(--bg-page)',
          border: '1px solid var(--border-subtle)', display: 'flex', alignItems: 'center', padding: '0 14px' }}>
          <span className="t-body" style={{ color: 'var(--text-tertiary)' }}>Message…</span>
        </div>
        <span style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--primary)', color: 'var(--text-on-primary)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="send" size={19} stroke={2} /></span>
      </div>
    </Screen>
  );
}

// ── Documents / coffre-fort ──
function DocRow({ icon, name, meta, badge, badgeTone, badgeIcon, last }) {
  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 0', borderBottom: last ? 'none' : '1px solid var(--border-subtle)' }}>
      <div style={{ width: 40, height: 40, borderRadius: 'var(--r-md)', background: 'var(--primary-subtle-bg)',
        color: 'var(--primary-subtle-fg)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon name={icon} size={20} stroke={2} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="t-label" style={{ color: 'var(--text-primary)' }}>{name}</div>
        <div className="t-micro" style={{ color: 'var(--text-tertiary)', fontWeight: 400 }}>{meta}</div>
      </div>
      {badge && <Badge tone={badgeTone} icon={badgeIcon}>{badge}</Badge>}
      <span style={{ color: 'var(--text-tertiary)' }}><Icon name="chevronR" size={18} stroke={2} /></span>
    </div>
  );
}

function ScreenDocuments({ dark }) {
  return (
    <Screen dark={dark} nav="docs">
      <Header title="Documents" trailing={<IconButton name="search" />} />
      <Scroll style={{ padding: '4px 20px 8px' }}>
        {/* action requise */}
        <div style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '14px', borderRadius: 'var(--r-lg)',
          background: 'var(--warning-bg)', marginBottom: 18 }}>
          <span style={{ color: 'var(--warning-fg)' }}><Icon name="document" size={22} stroke={2} /></span>
          <div style={{ flex: 1 }}>
            <div className="t-label" style={{ color: 'var(--warning-fg)' }}>1 devis à signer</div>
            <div className="t-micro" style={{ color: 'var(--warning-fg)', opacity: 0.85, fontWeight: 400 }}>Plan de soins · Dr Lefèvre</div>
          </div>
          <Button size="sm" variant="primary" style={{ background: 'var(--warning-fg)' }}>Ouvrir</Button>
        </div>

        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 6 }}>Devis & factures</div>
        <Card pad={16} style={{ marginBottom: 18, padding: '2px 16px' }}>
          <DocRow icon="document" name="Devis · Plan de soins" meta="Dr Lefèvre · 2 juin 2025" badge="À signer" badgeTone="warning" badgeIcon="clock" />
          <DocRow icon="euro" name="Facture · Détartrage" meta="12 mai 2025 · 60 €" badge="Payée" badgeTone="success" badgeIcon="check" last />
        </Card>

        <div className="t-label" style={{ color: 'var(--text-secondary)', marginBottom: 6 }}>Coffre-fort santé</div>
        <Card pad={16} style={{ padding: '2px 16px' }}>
          <DocRow icon="pill" name="Ordonnance · Amoxicilline" meta="Dr Lefèvre · 2 juin 2025" />
          <DocRow icon="image" name="Radio panoramique" meta="Centre d'imagerie · 28 mai" />
          <DocRow icon="document" name="Compte-rendu opératoire" meta="Dr Marin · 14 avr." last />
        </Card>
        <div style={{ height: 8 }} />
      </Scroll>
    </Screen>
  );
}

Object.assign(window, {
  Segmented, RdvCard, ScreenMesRDV, ScreenSalleAttente, ScreenTeleconsult,
  ScreenMessagerie, Bubble, ScreenConversation, DocRow, ScreenDocuments,
});
