// Nubia shared UI primitives + icon set. Consumes semantic tokens from tokens.css.
// All exported to window so sibling babel scripts can use them by bare name.

// ── Icons — simple feather-style line glyphs (24px grid, currentColor stroke) ──
const NB_ICONS = {
  home:        'M3 11.5 12 4l9 7.5M5 10v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9',
  search:      'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM20 20l-4-4',
  calendar:    'M7 3v3M17 3v3M4 8h16M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Z',
  message:     'M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-4 3v-3H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z',
  document:    'M6 3h7l5 5v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1ZM13 3v5h5',
  user:        'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM5 20a7 7 0 0 1 14 0',
  bell:        'M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6M10 21a2 2 0 0 0 4 0',
  lock:        'M7 10V7a5 5 0 0 1 10 0v3M5 10h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1Z',
  check:       'M5 12.5 10 17 19 7',
  checkCircle: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM8.5 12l2.5 2.5 4.5-5',
  chevronR:    'M9 5l7 7-7 7',
  chevronL:    'M15 5l-7 7 7 7',
  chevronD:    'M5 9l7 7 7-7',
  mapPin:      'M12 21s7-6.3 7-11a7 7 0 1 0-14 0c0 4.7 7 11 7 11ZM12 12a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z',
  phone:       'M5 4h3l2 5-2 1a11 11 0 0 0 5 5l1-2 5 2v3a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2Z',
  video:       'M3 7a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V7ZM15 10l6-3v10l-6-3',
  camera:      'M4 8h3l1.5-2h7L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1ZM12 17a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z',
  mic:         'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3ZM5 11a7 7 0 0 0 14 0M12 18v3',
  plus:        'M12 5v14M5 12h14',
  filter:      'M3 5h18l-7 8v6l-4-2v-4L3 5Z',
  sliders:     'M4 8h10M18 8h2M4 16h2M10 16h10M14 6v4M6 14v4',
  star:        'M12 4l2.4 4.9 5.4.8-3.9 3.8.9 5.4-4.8-2.5-4.8 2.5.9-5.4L4.2 9.7l5.4-.8L12 4Z',
  clock:       'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 7v5l3 2',
  shield:      'M12 3l7 3v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3ZM9 12l2 2 4-4',
  euro:        'M16 7a6 6 0 1 0 0 10M5 10h7M5 14h6',
  image:       'M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1ZM8 11a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM4 16l5-4 4 3 3-2 5 4',
  paperclip:   'M20 11l-8 8a5 5 0 0 1-7-7l8-8a3.3 3.3 0 0 1 5 5l-8 8a1.6 1.6 0 0 1-2.4-2.2L17 9',
  send:        'M21 4 3 11l7 2 2 7 9-16Z',
  arrowR:      'M5 12h14M13 6l6 6-6 6',
  x:           'M6 6l12 12M18 6 6 18',
  info:        'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 11v5M12 8h.01',
  alert:       'M12 4 2 19h20L12 4ZM12 10v4M12 17h.01',
  qr:          'M4 4h6v6H4V4ZM14 4h6v6h-6V4ZM4 14h6v6H4v-6ZM14 14h2v2h-2v-2ZM18 14h2v2h-2v-2ZM14 18h2v2h-2v-2ZM18 18h2v2h-2v-2Z',
  navigation:  'M21 4 3 11l8 2 2 8 8-17Z',
  heart:       'M12 20S4 15 4 9a4 4 0 0 1 8-1 4 4 0 0 1 8 1c0 6-8 11-8 11Z',
  list:        'M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01',
  map:         'M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2ZM9 4v14M15 6v14',
  refresh:     'M4 11a8 8 0 0 1 14-5l2 2M20 13a8 8 0 0 1-14 5l-2-2M18 4v4h-4M6 20v-4h4',
  edit:        'M5 19h14M14 5l4 4-9 9H5v-4l9-9Z',
  download:    'M12 4v11M7 11l5 5 5-5M5 20h14',
  pill:        'M8 4a4 4 0 0 0-4 4v8a4 4 0 0 0 8 0V8a4 4 0 0 0-4-4ZM4 12h8',
};

function Icon({ name, size = 22, stroke = 2, fill = false, style = {} }) {
  const d = NB_ICONS[name];
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
      style={{ display: 'block', flexShrink: 0, ...style }}>
      <path d={d} fill={fill ? 'currentColor' : 'none'} stroke={fill ? 'none' : 'currentColor'} />
    </svg>
  );
}

// ── Striped placeholder for real imagery (photos, maps) ──
function Placeholder({ label = 'image', height = 120, radius = 'var(--r-lg)', style = {} }) {
  return (
    <div style={{
      height, borderRadius: radius, position: 'relative', overflow: 'hidden',
      background: 'repeating-linear-gradient(135deg, var(--border-subtle) 0 10px, var(--bg-page) 10px 20px)',
      border: '1px solid var(--border-subtle)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', ...style,
    }}>
      <span style={{
        font: '500 11px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace',
        color: 'var(--text-tertiary)', letterSpacing: 0.4, background: 'var(--bg-surface)',
        padding: '3px 8px', borderRadius: 'var(--r-full)', textTransform: 'lowercase',
      }}>{label}</span>
    </div>
  );
}

// ── Avatar (initials, brand-tinted) ──
function Avatar({ initials, size = 44, tone = 'brand', style = {} }) {
  const tones = {
    brand: { bg: 'var(--primary-subtle-bg)', fg: 'var(--primary-subtle-fg)' },
    neutral: { bg: 'var(--n-100)', fg: 'var(--text-secondary)' },
    sand: { bg: 'var(--accent-100)', fg: 'var(--accent-700)' },
  }[tone];
  return (
    <div style={{
      width: size, height: size, borderRadius: 'var(--r-full)', flexShrink: 0,
      background: tones.bg, color: tones.fg,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontWeight: 600, fontSize: size * 0.36, letterSpacing: 0.2, ...style,
    }}>{initials}</div>
  );
}

// ── Button ──
function Button({ children, variant = 'primary', size = 'md', icon, iconRight, full = false, style = {}, onClick }) {
  const h = { sm: 36, md: 48, lg: 54 }[size];
  const base = {
    height: h, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
    borderRadius: 'var(--r-md)', border: '1px solid transparent', cursor: 'pointer',
    font: '500 16px/1 var(--font-ui)', padding: '0 20px', width: full ? '100%' : undefined,
    transition: 'background .12s, border-color .12s', whiteSpace: 'nowrap',
  };
  const variants = {
    primary: { background: 'var(--primary)', color: 'var(--text-on-primary)' },
    secondary: { background: 'var(--bg-surface)', color: 'var(--text-primary)', borderColor: 'var(--border-default)' },
    ghost: { background: 'transparent', color: 'var(--primary)' },
    danger: { background: 'var(--danger-bg)', color: 'var(--danger-fg)' },
  };
  return (
    <button onClick={onClick} style={{ ...base, ...variants[variant], ...style }}>
      {icon && <Icon name={icon} size={19} stroke={2.1} />}
      {children}
      {iconRight && <Icon name={iconRight} size={19} stroke={2.1} />}
    </button>
  );
}

// ── Chip / pill filter ──
function Chip({ children, icon, active = false, style = {} }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, height: 36, padding: '0 14px',
      borderRadius: 'var(--r-full)', font: '500 14px/1 var(--font-ui)', cursor: 'pointer',
      whiteSpace: 'nowrap', flexShrink: 0,
      background: active ? 'var(--primary-subtle-bg)' : 'var(--bg-surface)',
      color: active ? 'var(--primary-subtle-fg)' : 'var(--text-secondary)',
      border: `1px solid ${active ? 'transparent' : 'var(--border-subtle)'}`, ...style,
    }}>
      {icon && <Icon name={icon} size={16} stroke={2} />}
      {children}
    </span>
  );
}

// ── Status badge / pill (always icon + text, never color alone) ──
function Badge({ children, tone = 'neutral', icon, style = {} }) {
  const map = {
    neutral: { bg: 'var(--n-100)', fg: 'var(--text-secondary)' },
    success: { bg: 'var(--success-bg)', fg: 'var(--success-fg)' },
    warning: { bg: 'var(--warning-bg)', fg: 'var(--warning-fg)' },
    danger:  { bg: 'var(--danger-bg)', fg: 'var(--danger-fg)' },
    info:    { bg: 'var(--info-bg)', fg: 'var(--info-fg)' },
    brand:   { bg: 'var(--primary-subtle-bg)', fg: 'var(--primary-subtle-fg)' },
    sand:    { bg: 'var(--accent-100)', fg: 'var(--accent-700)' },
  }[tone];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4, padding: '3px 9px 3px 7px',
      borderRadius: 'var(--r-full)', font: '500 12px/1.3 var(--font-ui)', whiteSpace: 'nowrap',
      background: map.bg, color: map.fg, ...style,
    }}>
      {icon && <Icon name={icon} size={13} stroke={2.4} />}
      {children}
    </span>
  );
}

// ── Card ──
function Card({ children, selected = false, pad = 16, style = {}, onClick }) {
  return (
    <div onClick={onClick} style={{
      background: 'var(--bg-surface)', borderRadius: 'var(--r-lg)', padding: pad,
      border: `1px solid ${selected ? 'var(--primary)' : 'var(--border-subtle)'}`,
      boxShadow: 'var(--shadow-sm)', ...style,
    }}>{children}</div>
  );
}

// ── Screen scaffold: fills the device, clears status bar + home indicator ──
function Screen({ children, dark, nav, style = {} }) {
  return (
    <div className={'nubia' + (dark ? ' nubia-dark' : '')} style={{
      height: '100%', display: 'flex', flexDirection: 'column',
      background: 'var(--bg-page)', position: 'relative', ...style,
    }}>
      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {children}
      </div>
      {nav && <BottomNav active={nav} />}
    </div>
  );
}

// Standard header band (clears the status bar / dynamic island)
function Header({ title, display = false, trailing, leading, sub, style = {} }) {
  return (
    <div style={{
      padding: '58px 20px 12px', flexShrink: 0, background: 'var(--bg-page)',
      display: 'flex', alignItems: 'flex-end', gap: 12, ...style,
    }}>
      {leading}
      <div style={{ flex: 1, minWidth: 0 }}>
        {sub && <div className="t-caption" style={{ color: 'var(--text-tertiary)', marginBottom: 2 }}>{sub}</div>}
        <div className={display ? 't-display' : 't-h1'} style={{ color: 'var(--text-primary)' }}>{title}</div>
      </div>
      {trailing}
    </div>
  );
}

function IconButton({ name, badge = false, onClick, size = 22 }) {
  return (
    <button onClick={onClick} style={{
      width: 44, height: 44, borderRadius: 'var(--r-full)', border: '1px solid var(--border-subtle)',
      background: 'var(--bg-surface)', color: 'var(--text-secondary)', cursor: 'pointer',
      display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative', flexShrink: 0,
    }}>
      <Icon name={name} size={size} stroke={2} />
      {badge && <span style={{
        position: 'absolute', top: 9, right: 10, width: 8, height: 8, borderRadius: '50%',
        background: 'var(--danger-fg)', border: '1.5px solid var(--bg-surface)',
      }} />}
    </button>
  );
}

// ── Bottom navigation (5 tabs) ──
function BottomNav({ active = 'home' }) {
  const tabs = [
    { id: 'home', icon: 'search', label: 'Rechercher' },
    { id: 'rdv', icon: 'calendar', label: 'Mes RDV' },
    { id: 'msg', icon: 'message', label: 'Messages' },
    { id: 'docs', icon: 'document', label: 'Documents' },
    { id: 'profile', icon: 'user', label: 'Profil' },
  ];
  return (
    <div style={{
      flexShrink: 0, display: 'flex', justifyContent: 'space-around', alignItems: 'flex-start',
      padding: '10px 8px 30px', background: 'var(--bg-surface)',
      borderTop: '1px solid var(--border-subtle)',
    }}>
      {tabs.map(t => {
        const on = t.id === active;
        return (
          <div key={t.id} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            color: on ? 'var(--primary)' : 'var(--text-tertiary)', flex: 1, position: 'relative',
          }}>
            <Icon name={t.icon} size={24} stroke={on ? 2.3 : 1.9} fill={false} />
            <span style={{ font: `${on ? 600 : 500} 10px/1 var(--font-ui)`, letterSpacing: 0.1 }}>{t.label}</span>
            {t.id === 'docs' && (
              <span style={{
                position: 'absolute', top: -2, right: '50%', marginRight: -22,
                minWidth: 16, height: 16, padding: '0 4px', borderRadius: 8,
                background: 'var(--danger-fg)', color: '#fff', font: '600 10px/16px var(--font-ui)',
                textAlign: 'center',
              }}>1</span>
            )}
          </div>
        );
      })}
    </div>
  );
}

// scrollable content region inside a screen
function Scroll({ children, style = {} }) {
  return <div style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden', ...style }}>{children}</div>;
}

Object.assign(window, {
  NB_ICONS, Icon, Placeholder, Avatar, Button, Chip, Badge, Card,
  Screen, Header, IconButton, BottomNav, Scroll,
});
