import { useState, useEffect, useRef } from 'preact/hooks';
import { getMe, selectContext } from '../lib/api/context';
import { getContext, login } from '../lib/session';
import type { MeContext } from '../lib/api/types';

function contextLabel(ctx: MeContext): string {
  return ctx.secretariat_name
    ? `${ctx.cabinet_name ?? ctx.cabinet_id} — ${ctx.secretariat_name}`
    : (ctx.cabinet_name ?? ctx.cabinet_id);
}

function ctxKey(ctx: MeContext): string {
  return ctx.cabinet_id + '|' + (ctx.secretariat_id ?? '');
}

export default function ContextSwitcher() {
  const [contexts, setContexts] = useState<MeContext[]>([]);
  const [open, setOpen] = useState(false);
  const [activeKey, setActiveKey] = useState<string>('');
  const [busy, setBusy] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const current = getContext();
    if (current) {
      setActiveKey(current.cabinet_id + '|' + (current.secretariat_id ?? ''));
    }

    getMe()
      .then(me => {
        const ctxs: MeContext[] =
          me.contexts && me.contexts.length > 0
            ? me.contexts
            : (me.memberships ?? []).map(m => ({
                cabinet_id: m.cabinet_id,
                role: m.role,
                secretariat_id: m.secretariat_id,
              }));
        setContexts(ctxs);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (!open) return;
    function onOutsideClick(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', onOutsideClick);
    return () => document.removeEventListener('mousedown', onOutsideClick);
  }, [open]);

  if (contexts.length <= 1) return null;

  const active = contexts.find(c => ctxKey(c) === activeKey) ?? contexts[0];

  async function handleSelect(ctx: MeContext) {
    if (busy || ctxKey(ctx) === activeKey) return;
    setBusy(true);
    setOpen(false);
    try {
      const result = await selectContext({
        cabinet_id: ctx.cabinet_id,
        secretariat_id: ctx.secretariat_id,
      });
      login(result.access_token);
      window.location.reload();
    } catch {
      setBusy(false);
    }
  }

  return (
    <div class="ctx-switcher" ref={containerRef}>
      <button
        type="button"
        class="ctx-switcher__trigger"
        onClick={() => setOpen(o => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label="Changer de contexte"
        disabled={busy}
      >
        <span class="ctx-switcher__label">{contextLabel(active)}</span>
        <span class="ctx-switcher__chevron" aria-hidden="true">▾</span>
      </button>

      {open && (
        <ul class="ctx-switcher__list" role="listbox" aria-label="Contextes disponibles">
          {contexts.map(ctx => {
            const isCurrent = ctxKey(ctx) === activeKey;
            return (
              <li
                key={ctxKey(ctx)}
                class="ctx-switcher__item"
                role="option"
                aria-selected={isCurrent}
              >
                <button
                  type="button"
                  class={`ctx-switcher__option${isCurrent ? ' ctx-switcher__option--current' : ''}`}
                  onClick={() => handleSelect(ctx)}
                  disabled={busy || isCurrent}
                >
                  <span
                    class={`ctx-switcher__check${isCurrent ? '' : ' ctx-switcher__check--empty'}`}
                    aria-hidden="true"
                  >
                    {isCurrent ? '✓' : ''}
                  </span>
                  {contextLabel(ctx)}
                </button>
              </li>
            );
          })}
        </ul>
      )}

      <style>{`
        .ctx-switcher {
          position: relative;
          display: inline-block;
        }

        .ctx-switcher__trigger {
          display: inline-flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          background: var(--color-surface);
          border: 1px solid var(--color-border);
          border-radius: var(--radius-sm);
          color: var(--color-text);
          font-family: var(--font-sans);
          font-size: var(--font-size-sm);
          font-weight: 500;
          cursor: pointer;
          user-select: none;
        }

        .ctx-switcher__trigger:hover:not(:disabled) {
          background: var(--color-border);
        }

        .ctx-switcher__trigger[aria-expanded="true"] {
          border-color: var(--color-accent);
          outline: 2px solid var(--color-accent);
          outline-offset: 2px;
        }

        .ctx-switcher__trigger[aria-expanded="true"] .ctx-switcher__chevron {
          transform: rotate(180deg);
        }

        .ctx-switcher__label {
          max-width: 200px;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .ctx-switcher__chevron {
          font-size: var(--font-size-xs);
          color: var(--color-muted);
          flex-shrink: 0;
          transition: transform 0.15s;
        }

        .ctx-switcher__list {
          position: absolute;
          top: calc(100% + var(--space-1));
          left: 0;
          z-index: 100;
          min-width: 220px;
          margin: 0;
          padding: var(--space-1) 0;
          list-style: none;
          background: var(--color-surface);
          border: 1px solid var(--color-border);
          border-radius: var(--radius-md);
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
        }

        .ctx-switcher__item {
          display: block;
        }

        .ctx-switcher__option {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          width: 100%;
          padding: var(--space-2) var(--space-3);
          background: transparent;
          border: none;
          color: var(--color-text);
          font-family: var(--font-sans);
          font-size: var(--font-size-sm);
          text-align: left;
          cursor: pointer;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .ctx-switcher__option:hover:not(:disabled) {
          background: var(--color-border);
        }

        .ctx-switcher__option--current {
          color: var(--color-accent);
          font-weight: 600;
          cursor: default;
        }

        .ctx-switcher__check {
          font-size: var(--font-size-xs);
          width: 1em;
          flex-shrink: 0;
          color: var(--color-accent);
        }

        .ctx-switcher__check--empty {
          display: inline-block;
          width: 1em;
        }
      `}</style>
    </div>
  );
}
